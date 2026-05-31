<?php

namespace App\Events;

use App\Models\Device;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Event Reverb broadcasté quand un téléphone vient de faire son handshake.
 * Le dashboard /devices (S2.J4) écoute pour afficher le popup d'approbation.
 *
 * Canal PRIVÉ : la charge contient l'empreinte du device. Sans callback
 * d'autorisation déclaré dans channels.php, toute souscription est refusée
 * (la fuite reste fermée tant que l'auth dashboard n'est pas câblée — S3).
 */
class PairingPendingApproval implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public readonly Device $device,
    ) {
    }

    public function broadcastOn(): array
    {
        return [new PrivateChannel('linkup-pairing')];
    }

    public function broadcastAs(): string
    {
        return 'pairing.pending';
    }

    public function broadcastWith(): array
    {
        return [
            'device_id' => $this->device->id,
            'name' => $this->device->name,
            'fingerprint' => $this->device->fingerprint_sha256,
            'paired_at' => $this->device->paired_at?->toIso8601String(),
        ];
    }
}
