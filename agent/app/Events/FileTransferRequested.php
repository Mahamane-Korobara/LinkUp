<?php

namespace App\Events;

use App\Models\Transfer;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * S4.J2 (T4.8) — un transfert vient d'être initié, notifie l'autre côté.
 *
 * Canal privé (cf. PairingPendingApproval) : pas de souscription tant que
 * l'auth temps réel n'est pas câblée. Le polling du statut reste la voie
 * actuelle.
 */
class FileTransferRequested implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly Transfer $transfer,
    ) {
    }

    public function broadcastOn(): array
    {
        return [new PrivateChannel('linkup-transfers')];
    }

    public function broadcastAs(): string
    {
        return 'transfer.requested';
    }

    public function broadcastWith(): array
    {
        return [
            'transfer_id' => $this->transfer->id,
            'device_id' => $this->transfer->device_id,
            'filename' => $this->transfer->filename,
            'size' => $this->transfer->size,
            'direction' => $this->transfer->direction,
            'status' => $this->transfer->status,
        ];
    }
}
