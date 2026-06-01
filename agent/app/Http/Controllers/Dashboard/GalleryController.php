<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\GalleryItem;
use App\Services\Gallery\GalleryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * S6 — galerie distante vue depuis le dashboard PC (auth dashboard.client).
 *
 * Lecture seule : parcourt l'index poussé par les téléphones et sert les
 * vignettes. L'import des originaux est déclenché ailleurs (module transfert).
 */
class GalleryController extends Controller
{
    public function __construct(
        private readonly GalleryService $gallery,
    ) {
    }

    /**
     * GET /api/gallery?page=&size=&device_id= — index paginé (récent d'abord).
     */
    public function index(Request $request): JsonResponse
    {
        $page = max(1, (int) $request->query('page', '1'));
        $size = min(100, max(1, (int) $request->query('size', '50')));
        $deviceId = $request->query('device_id');

        $paginator = $this->gallery->paginate(is_string($deviceId) ? $deviceId : null, $page, $size);

        $statuses = $this->gallery->importStatuses(
            collect($paginator->items())->pluck('id')->all(),
        );

        return response()->json([
            'items' => collect($paginator->items())->map(fn (GalleryItem $i) => [
                'id' => $i->id,
                'device_id' => $i->device_id,
                'media_id' => $i->media_id,
                'mime' => $i->mime,
                'size' => $i->size,
                'taken_at' => $i->taken_at?->toIso8601String(),
                'width' => $i->width,
                'height' => $i->height,
                'has_thumb' => $i->has_thumb,
                // null | 'requested' | 'done' : où en est l'import de l'original.
                'import_status' => $statuses[$i->id] ?? null,
            ]),
            'page' => $paginator->currentPage(),
            'last_page' => $paginator->lastPage(),
            'total' => $paginator->total(),
        ]);
    }

    /**
     * POST /api/gallery/import — demande l'import des originaux (sélection
     * dashboard). Crée des demandes `requested` que le tél honorera en polling.
     * Body : `ids` = identifiants de `gallery_items`.
     */
    public function requestImport(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'ids' => 'required|array|min:1|max:200',
            'ids.*' => 'required|string|max:64',
        ]);

        $count = $this->gallery->requestImports($validated['ids']);

        return response()->json(['ok' => true, 'requested' => $count]);
    }

    /**
     * GET /api/gallery/{item}/thumb — sert la vignette JPEG (404 si absente).
     */
    public function thumb(GalleryItem $item): Response
    {
        $path = $this->gallery->thumbnailAbsolutePath($item);
        abort_if($path === null, 404);

        return response()->file($path, [
            'Content-Type' => 'image/jpeg',
            'Cache-Control' => 'private, max-age=3600',
        ]);
    }
}
