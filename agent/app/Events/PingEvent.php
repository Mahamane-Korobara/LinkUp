<?php

namespace App\Events;

use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class PingEvent implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public string $message;

    public int $emittedAt;

    public function __construct(string $message = 'pong', ?int $emittedAt = null)
    {
        $this->message = $message;
        $this->emittedAt = $emittedAt ?? time();
    }

    public function broadcastOn(): array
    {
        return [new Channel('linkup-system')];
    }

    public function broadcastAs(): string
    {
        return 'ping';
    }

    public function broadcastWith(): array
    {
        return [
            'message' => $this->message,
            'emitted_at' => $this->emittedAt,
        ];
    }
}
