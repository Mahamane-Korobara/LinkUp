<?php

use App\Services\Crypto\KeyManager;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

it('returns 503 when bridge responds with HTTP 5xx', function () {
    Http::fake([
        'http://127.0.0.1:8765/mdns/info' => Http::response(null, 500),
    ]);

    $this->getJson('/api/agent/info')
        ->assertStatus(503)
        ->assertJsonStructure(['error']);
});

it('returns 503 when bridge is totally unreachable (ConnectionException)', function () {
    Http::fake(function () {
        throw new ConnectionException('Connection refused');
    });

    $this->getJson('/api/agent/info')
        ->assertStatus(503)
        ->assertJsonPath('error', fn ($msg) => str_contains((string) $msg, 'injoignable'));
});

it('proxies local mDNS agent info through Laravel with the real Ed25519 fingerprint', function () {
    // KeyManager isolé sur un dossier temp : on ne touche pas la vraie paire ~/.linkup.
    $home = sys_get_temp_dir() . '/linkup-test-' . uniqid();
    $keys = new KeyManager($home);
    $this->app->instance(KeyManager::class, $keys);

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
            // L'empreinte renvoyée est celle du KeyManager, PAS le 'pending' du bridge.
            'fingerprint' => $keys->fingerprint(),
            'agent_id' => 'linkup-test',
            'version' => '0.1.0',
            'reverb_port' => 8080,
            'bridge_port' => 8765,
            'source' => 'bridge',
        ]);

    expect($response->json('fingerprint'))
        ->not->toBe('pending')
        ->toMatch('/^[0-9a-f]{8}$/');

    // Nettoyage du dossier temp de clés.
    @unlink("$home/.linkup/keys/agent_ed25519.pub");
    @unlink("$home/.linkup/keys/agent_ed25519.sec");
    @rmdir("$home/.linkup/keys");
    @rmdir("$home/.linkup");
    @rmdir($home);
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
