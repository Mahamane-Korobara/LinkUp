<?php

namespace App\Http\Controllers\Gallery;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AuthenticateDevice;
use App\Models\Device;
use App\Models\GalleryImportRequest;
use App\Models\GalleryItem;
use App\Services\Gallery\GalleryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * S6 — endpoints galerie côté téléphone (auth.device). Le tél pousse l'index de
 * sa galerie (métadonnées) puis les vignettes ; les originaux ne partent qu'à
 * l'import (module transfert S4).
 */
class GalleryController extends Controller
{
    public function __construct(
        private readonly GalleryService $gallery,
    ) {
    }

    /**
     * POST /api/gallery/sync — upsert un lot de métadonnées.
     * Réponse : `pending_thumbs` = media_id sans vignette (à envoyer ensuite).
     */
    public function sync(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'items' => 'required|array|max:500',
            'items.*.media_id' => 'required|string|max:191',
            // Règle en TABLEAU : la regex contient un « | » que Laravel couperait
            // en notation pipe.
            'items.*.mime' => ['required', 'string', 'max:64', 'regex:#^(image|video)/#'],
            'items.*.size' => 'sometimes|integer|min:0',
            'items.*.taken_at' => 'sometimes|nullable|date',
            'items.*.width' => 'sometimes|nullable|integer|min:0',
            'items.*.height' => 'sometimes|nullable|integer|min:0',
        ]);

        $pending = $this->gallery->syncBatch($this->device($request), $validated['items']);

        return response()->json(['ok' => true, 'pending_thumbs' => $pending]);
    }

    /**
     * POST /api/gallery/thumb — corps brut = JPEG de la vignette, header
     * `X-Media-Id` = media concerné. Le media doit avoir été syncé d'abord.
     */
    public function thumb(Request $request): JsonResponse
    {
        $mediaId = (string) $request->header('X-Media-Id', '');
        if ($mediaId === '') {
            return response()->json(['message' => 'Header X-Media-Id manquant.'], 422);
        }

        $bytes = $request->getContent();
        if ($bytes === '') {
            return response()->json(['message' => 'Vignette vide.'], 422);
        }
        if (strlen($bytes) > GalleryService::MAX_THUMB_BYTES) {
            return response()->json(['message' => 'Vignette trop volumineuse.'], 422);
        }

        $item = GalleryItem::query()
            ->where('device_id', $this->device($request)->id)
            ->where('media_id', $mediaId)
            ->first();

        if ($item === null) {
            return response()->json(['message' => 'Média inconnu — synchronise d\'abord.'], 404);
        }

        $this->gallery->storeThumbnail($item, $bytes);

        return response()->json(['ok' => true, 'id' => $item->id]);
    }

    /**
     * GET /api/gallery/imports — demandes d'import en attente pour ce tél.
     * Le tél les honore en uploadant les originaux via le module transfert (S4),
     * puis appelle /done pour chacune.
     */
    public function pendingImports(Request $request): JsonResponse
    {
        $pending = $this->gallery->pendingImports($this->device($request))->map(fn (GalleryImportRequest $r) => [
            'id' => $r->id,
            'media_id' => $r->media_id,
            'mime' => $r->item?->mime,
            'size' => $r->item?->size,
        ]);

        return response()->json(['imports' => $pending->values()]);
    }

    /**
     * POST /api/gallery/imports/{import}/done — le tél confirme avoir uploadé
     * l'original, en pointant le transfert produit.
     */
    public function markImported(Request $request, GalleryImportRequest $import): JsonResponse
    {
        // Anti-IDOR : un device ne marque QUE ses propres demandes.
        abort_unless($import->device_id === $this->device($request)->id, 404);

        $validated = $request->validate([
            'transfer_id' => 'sometimes|nullable|string|max:64',
        ]);

        $this->gallery->markImported($import, $validated['transfer_id'] ?? null);

        return response()->json(['ok' => true]);
    }

    private function device(Request $request): Device
    {
        return $request->attributes->get(AuthenticateDevice::ATTRIBUTE);
    }
}
