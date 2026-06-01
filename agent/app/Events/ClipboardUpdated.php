<?php

namespace App\Events;

use App\Models\ClipboardEntry;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * S5 — un contenu de presse-papier vient d'être synchronisé, notifie les autres
 * devices (le tél affiche « Texte copié depuis le PC », etc.).
 *
 * Canal PRIVÉ (cf. PairingPendingApproval) : pas de souscription tant que l'auth
 * temps réel n'est pas câblée. Le polling reste la voie actuelle ; on ne diffuse
 * QU'UN aperçu, jamais le contenu complet (qui peut être sensible).
 */
class ClipboardUpdated implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly ClipboardEntry $entry,
    ) {
    }

    public function broadcastOn(): array
    {
        return [new PrivateChannel('linkup-clipboard')];
    }

    public function broadcastAs(): string
    {
        return 'clipboard.updated';
    }

    public function broadcastWith(): array
    {
        return [
            'id' => $this->entry->id,
            'device_id' => $this->entry->device_id,
            'origin' => $this->entry->origin,
            // Aperçu seulement : le contenu complet se récupère via l'API authentifiée.
            'preview' => mb_substr($this->entry->content, 0, 120),
            'created_at' => $this->entry->created_at?->toIso8601String(),
        ];
    }
}
