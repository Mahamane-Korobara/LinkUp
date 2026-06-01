<?php

namespace App\Services\Gallery;

use App\Models\Device;
use App\Models\GalleryItem;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\Storage;

/**
 * S6 — orchestration de la galerie distante.
 *
 * Indexe les métadonnées poussées par le tél, stocke les vignettes sur disque
 * (disque `local`, hors web root), et pagine pour le dashboard.
 */
class GalleryService
{
    /** Plafond raisonnable pour une vignette 200×200 JPEG. */
    public const MAX_THUMB_BYTES = 512 * 1024;

    private function disk(): Filesystem
    {
        return Storage::disk('local');
    }

    /**
     * Chemin RELATIF (sur le disque local) de la vignette d'un item.
     *
     * Le nom de fichier est un sha1 du media_id → aucun risque de traversal même
     * si le tél envoie un media_id contenant des `/` (content URIs).
     */
    private function thumbRelativePath(string $deviceId, string $mediaId): string
    {
        return "gallery/{$deviceId}/" . sha1($mediaId) . '.jpg';
    }

    /**
     * Upsert un lot de métadonnées. Retourne les `media_id` qui n'ont pas encore
     * de vignette (pour que le tél sache lesquelles générer + envoyer).
     *
     * @param  array<int, array<string, mixed>>  $items
     * @return array<int, string>
     */
    public function syncBatch(Device $device, array $items): array
    {
        $pending = [];
        foreach ($items as $it) {
            $entry = GalleryItem::updateOrCreate(
                ['device_id' => $device->id, 'media_id' => (string) $it['media_id']],
                [
                    'mime' => (string) $it['mime'],
                    'size' => (int) ($it['size'] ?? 0),
                    'taken_at' => $it['taken_at'] ?? null,
                    'width' => $it['width'] ?? null,
                    'height' => $it['height'] ?? null,
                ],
            );
            if (! $entry->has_thumb) {
                $pending[] = $entry->media_id;
            }
        }

        return $pending;
    }

    /** Écrit la vignette d'un item sur disque et marque `has_thumb`. */
    public function storeThumbnail(GalleryItem $item, string $jpegBytes): void
    {
        $this->disk()->put($this->thumbRelativePath($item->device_id, $item->media_id), $jpegBytes);
        $item->forceFill(['has_thumb' => true])->save();
    }

    /** Liste paginée pour le dashboard (plus récentes d'abord). */
    public function paginate(?string $deviceId, int $page, int $size): LengthAwarePaginator
    {
        return GalleryItem::query()
            ->when($deviceId, fn ($q) => $q->where('device_id', $deviceId))
            ->orderByDesc('taken_at')
            ->orderByDesc('id')
            ->paginate(perPage: $size, page: $page);
    }

    /** Chemin ABSOLU de la vignette (pour la servir), ou null si absente. */
    public function thumbnailAbsolutePath(GalleryItem $item): ?string
    {
        if (! $item->has_thumb) {
            return null;
        }
        $rel = $this->thumbRelativePath($item->device_id, $item->media_id);

        return $this->disk()->exists($rel) ? $this->disk()->path($rel) : null;
    }
}
