<?php

namespace App\Events;

use App\Models\Device;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Event Reverb broadcasté quand un téléphone vient de faire son handshake.
 * Le dashboard /devices (S2.J4) écoute pour afficher le popup d'approbation.
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
        return [new Channel('linkup-pairing')];
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
