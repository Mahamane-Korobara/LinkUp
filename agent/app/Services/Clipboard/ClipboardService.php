<?php

namespace App\Services\Clipboard;

use App\Events\ClipboardUpdated;
use App\Models\ClipboardEntry;
use App\Models\Device;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * S5 — orchestration du presse-papier synchronisé.
 *
 * Journalise les contenus échangés et notifie via Reverb. Le `bridge` Python
 * touche réellement le presse-papier de l'OS (cf. BridgeClient::writeClipboard).
 */
class ClipboardService
{
    public const ORIGIN_PHONE = 'phone';
    public const ORIGIN_PC = 'pc';

    /**
     * Fenêtre anti-boucle : un MÊME contenu revu dans ce délai est ignoré, pour
     * éviter qu'un aller-retour tél↔PC ne fasse boucler le même texte.
     */
    private const DEDUP_TTL_SECONDS = 2;

    /**
     * Journalise un contenu de presse-papier et le diffuse.
     *
     * Anti-boucle : si le même contenu (hash) a déjà été vu il y a moins de
     * {@see DEDUP_TTL_SECONDS} secondes, on l'ignore et on retourne `null`.
     */
    public function receive(?Device $device, string $content, string $origin): ?ClipboardEntry
    {
        $hash = hash('sha256', $content);

        // Cache::add est atomique : retourne false si la clé existe déjà → le
        // contenu a été vu il y a moins du TTL, on coupe la boucle.
        $fresh = Cache::add("clipboard:seen:{$hash}", true, now()->addSeconds(self::DEDUP_TTL_SECONDS));
        if (! $fresh) {
            return null;
        }

        $entry = ClipboardEntry::create([
            'device_id' => $device?->id,
            'content' => $content,
            'hash' => $hash,
            'origin' => $origin,
        ]);

        // Best-effort : un Reverb indisponible ne doit pas faire échouer la sync.
        try {
            ClipboardUpdated::dispatch($entry);
        } catch (\Throwable $e) {
            Log::warning('Broadcast ClipboardUpdated échoué : ' . $e->getMessage());
        }

        return $entry;
    }

    /**
     * Historique récent du presse-papier pour ce device (récents d'abord).
     *
     * @return Collection<int, ClipboardEntry>
     */
    public function recent(Device $device, int $limit = 50): Collection
    {
        return ClipboardEntry::query()
            ->where('device_id', $device->id)
            ->latest()
            ->limit($limit)
            ->get();
    }
}
