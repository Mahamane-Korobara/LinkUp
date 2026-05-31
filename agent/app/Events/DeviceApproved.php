<?php

namespace App\Events;

use App\Models\Device;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * S2.J4 (T2.18) — broadcasté quand le PC approuve un device.
 *
 * Notifie le dashboard (retrait du popup) et, à terme (S2.J5), le canal
 * privé du device pour réveiller le tel. Le token NE transite JAMAIS dans
 * cet event : il n'est délivré qu'au tel authentifié via la poll.
 *
 * Canal PRIVÉ (cf. PairingPendingApproval) : souscription refusée tant que
 * l'auth dashboard n'est pas câblée (S3).
 */
class DeviceApproved implements ShouldBroadcastNow
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
        return 'device.approved';
    }

    public function broadcastWith(): array
    {
        return [
            'device_id' => $this->device->id,
            'name' => $this->device->name,
            'fingerprint' => $this->device->fingerprint_sha256,
            'approved_at' => $this->device->approved_at?->toIso8601String(),
        ];
    }
}
