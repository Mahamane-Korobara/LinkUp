<?php

use App\Events\PingEvent;
use Illuminate\Broadcasting\Channel;
use Illuminate\Support\Facades\Event;

it('exposes a healthy /api/health endpoint', function () {
    $response = $this->getJson('/api/health');

    $response->assertOk()
        ->assertJson([
            'status' => 'ok',
            'service' => 'linkup-agent',
        ])
        ->assertJsonStructure(['status', 'service', 'version', 'time']);
});

it('broadcasts a PingEvent when /api/ping is hit', function () {
    Event::fake([PingEvent::class]);

    $response = $this->postJson('/api/ping', ['message' => 'hello-from-test']);

    $response->assertOk()
        ->assertJson([
            'broadcasted' => true,
            'channel' => 'linkup-system',
            'event' => 'ping',
            'message' => 'hello-from-test',
        ]);

    Event::assertDispatched(PingEvent::class, function (PingEvent $event) {
        return $event->message === 'hello-from-test';
    });
});

it('uses the linkup-system public channel and "ping" alias', function () {
    $event = new PingEvent('hello');

    $channels = $event->broadcastOn();

    expect($channels)->toHaveCount(1)
        ->and($channels[0])->toBeInstanceOf(Channel::class)
        ->and($channels[0]->name)->toBe('linkup-system')
        ->and($event->broadcastAs())->toBe('ping');
});

it('serializes payload with message and emitted_at timestamp', function () {
    $event = new PingEvent('hi', 1_700_000_000);

    $payload = $event->broadcastWith();

    expect($payload)
        ->toHaveKeys(['message', 'emitted_at'])
        ->and($payload['message'])->toBe('hi')
        ->and($payload['emitted_at'])->toBe(1_700_000_000);
});

it('defaults the message to "pong" and emitted_at to now', function () {
    $before = time();
    $event = new PingEvent;
    $after = time();

    expect($event->message)->toBe('pong')
        ->and($event->emittedAt)->toBeGreaterThanOrEqual($before)
        ->and($event->emittedAt)->toBeLessThanOrEqual($after);
});
