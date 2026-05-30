<?php

use Illuminate\Support\Facades\Http;

it('returns 503 when bridge is down (connection refused)', function () {
    Http::fake([
        'http://127.0.0.1:8765/mdns/info' => Http::response(null, 500),
    ]);

    $this->getJson('/api/agent/info')
        ->assertStatus(503)
        ->assertJsonStructure(['error']);
});

it('proxies local mDNS agent info through Laravel', function () {
    Http::fake([
        'http://127.0.0.1:8765/mdns/info' => Http::response([
            'registered' => true,
            'instance_name' => 'linkup-test._linkup._tcp.local.',
            'agent_id' => 'linkup-test',
            'fingerprint' => 'pending',
            'version' => '0.1.0',
            'port' => 8080,
            'bridge_port' => 8765,
            'host' => 'laptop.local.',
            'ip' => '192.168.1.42',
        ], 200),
    ]);

    $response = $this->getJson('/api/agent/info');

    $response->assertOk()
        ->assertJson([
            'name' => 'linkup-test._linkup._tcp.local.',
            'fingerprint' => 'pending',
            'agent_id' => 'linkup-test',
            'version' => '0.1.0',
            'reverb_port' => 8080,
            'bridge_port' => 8765,
            'source' => 'bridge',
        ]);
});

it('proxies discovered mDNS services through Laravel', function () {
    Http::fake([
        'http://127.0.0.1:8765/mdns/services' => Http::response([
            'count' => 1,
            'agents' => [
                [
                    'name' => 'linkup-alpha._linkup._tcp.local.',
                    'host' => 'alpha.local.',
                    'addresses' => ['192.168.1.50'],
                    'port' => 8080,
                    'properties' => [
                        'bridge_port' => '8765',
                        'id' => 'linkup-alpha',
                    ],
                    'last_seen' => now()->toIso8601String(),
                ],
            ],
        ], 200),
    ]);

    $response = $this->getJson('/api/mdns/services');

    $response->assertOk()
        ->assertJsonPath('count', 1)
        ->assertJsonPath('agents.0.properties.id', 'linkup-alpha');
});
