<?php

namespace App\Http\Controllers\Gallery;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AuthenticateDevice;
use App\Models\Device;
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

    private function device(Request $request): Device
    {
        return $request->attributes->get(AuthenticateDevice::ATTRIBUTE);
    }
}
