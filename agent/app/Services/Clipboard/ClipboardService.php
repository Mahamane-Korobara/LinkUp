<?php

namespace App\Services\Clipboard;

use App\Events\ClipboardUpdated;
use App\Models\ClipboardEntry;
use App\Models\Device;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
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

    /** Rétention : le presse-papier journalisé est effacé après 2 jours. */
    public const RETENTION_DAYS = 2;

    /** Date limite : les entrées antérieures sont considérées expirées. */
    private function cutoff(): Carbon
    {
        return now()->subDays(self::RETENTION_DAYS);
    }

    /**
     * Supprime les entrées plus vieilles que la rétention. Retourne le nombre
     * d'entrées effacées. Appelé à chaque écriture (garantit la purge même sans
     * planificateur) et par la commande `clipboard:prune`.
     */
    public function prune(): int
    {
        return ClipboardEntry::query()->where('created_at', '<', $this->cutoff())->delete();
    }

    /**
     * Journalise un contenu de presse-papier et le diffuse.
     *
     * Anti-boucle / anti-doublon : si la DERNIÈRE entrée a déjà ce contenu, on
     * ne re-journalise pas (retourne `null`). Indispensable car le presse-papier
     * du PC est tiré en boucle en mode auto (poll) sans forcément changer —
     * sinon l'historique se remplirait du même texte indéfiniment.
     */
    public function receive(?Device $device, string $content, string $origin): ?ClipboardEntry
    {
        // Purge opportuniste : à chaque échange, on efface ce qui a plus de 2 j.
        $this->prune();

        $hash = hash('sha256', $content);

        if (ClipboardEntry::query()->latest()->value('hash') === $hash) {
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
            ->where('created_at', '>=', $this->cutoff()) // jamais d'entrée expirée
            ->latest()
            ->limit($limit)
            ->get();
    }

    /**
     * Historique récent, tous devices confondus (vue dashboard du PC).
     *
     * @return Collection<int, ClipboardEntry>
     */
    public function recentAll(int $limit = 100): Collection
    {
        return ClipboardEntry::query()
            ->where('created_at', '>=', $this->cutoff())
            ->latest()
            ->limit($limit)
            ->get();
    }
}
