<?php

use App\Models\Device;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Pairing\DeviceApprovalService;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/** En-têtes du client dashboard (anti-CSRF), exigés par dashboard.client. */
const DASH = ['X-Linkup-Client' => 'dashboard', 'Accept' => 'application/json'];

/** Device approuvé + token clair, pour tester les routes tél (auth.device). */
function previewDeviceWithToken(): array
{
    $kp = sodium_crypto_sign_keypair();
    $pub = base64_encode(sodium_crypto_sign_publickey($kp));
    $device = Device::create([
        'name' => 'Phone',
        'public_key' => $pub,
        'fingerprint_sha256' => substr(hash('sha256', base64_decode($pub)), 0, 8),
        'approved' => true,
        'approved_at' => now(),
        'paired_at' => now(),
    ]);

    return [$device, app(DeviceApprovalService::class)->issueTokenOnce($device)];
}

it('lists dev servers detected on the PC', function () {
    $this->mock(BridgeClient::class)
        ->shouldReceive('previewPorts')
        ->once()
        ->andReturn(['ports' => [['port' => 5173, 'process' => 'node']]]);

    $this->withHeaders(DASH)
        ->getJson('/api/preview/ports')
        ->assertOk()
        ->assertJsonPath('ports.0.port', 5173)
        ->assertJsonPath('ports.0.process', 'node');
});

it('exposes a port and relays the bridge response', function () {
    $this->mock(BridgeClient::class)
        ->shouldReceive('exposePreview')
        ->once()
        ->with(5173)
        ->andReturn([
            'target_port' => 5173,
            'listen_port' => 41234,
            'scheme' => 'https',
            'hosts' => ['192.168.1.10'],
        ]);

    $this->withHeaders(DASH)
        ->postJson('/api/preview/expose', ['port' => 5173])
        ->assertOk()
        ->assertJsonPath('listen_port', 41234)
        ->assertJsonPath('scheme', 'https')
        ->assertJsonPath('hosts.0', '192.168.1.10');
});

it('rejects an invalid port (422)', function () {
    $this->mock(BridgeClient::class)->shouldReceive('exposePreview')->never();

    $this->withHeaders(DASH)
        ->postJson('/api/preview/expose', ['port' => 70000])
        ->assertStatus(422);
});

it('returns 503 with the bridge message when the bridge is down', function () {
    $this->mock(BridgeClient::class)
        ->shouldReceive('exposePreview')
        ->andThrow(new BridgeUnavailableException("Aucun service n'écoute sur le port 9999."));

    $this->withHeaders(DASH)
        ->postJson('/api/preview/expose', ['port' => 9999])
        ->assertStatus(503)
        ->assertJsonPath('message', "Aucun service n'écoute sur le port 9999.");
});

it('refuses preview routes without the dashboard header (403)', function () {
    $this->getJson('/api/preview/ports')->assertStatus(403);
});

// ------------------------------------------------------------------ côté tél

it('lets a paired phone list exposed projects', function () {
    [$device, $token] = previewDeviceWithToken();

    $this->mock(BridgeClient::class)
        ->shouldReceive('exposedPreviews')
        ->once()
        ->andReturn([
            'exposed' => [['target_port' => 5173, 'listen_port' => 41234, 'started_at' => 0]],
            'scheme' => 'https',
            'hosts' => ['192.168.1.10'],
        ]);

    $this->withHeaders(['X-Device-Id' => $device->id, 'Authorization' => "Bearer {$token}"])
        ->getJson('/api/preview/projects')
        ->assertOk()
        ->assertJsonPath('exposed.0.listen_port', 41234)
        ->assertJsonPath('hosts.0', '192.168.1.10');
});

it('refuses the phone projects list without a device token (401)', function () {
    $this->getJson('/api/preview/projects')->assertStatus(401);
});

it('serves the public CA certificate without auth', function () {
    $this->mock(BridgeClient::class)
        ->shouldReceive('previewCaCertificate')
        ->once()
        ->andReturn("-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----\n");

    $res = $this->get('/api/preview/ca.crt');

    $res->assertOk();
    expect($res->headers->get('Content-Type'))->toContain('application/x-x509-ca-cert');
    expect($res->getContent())->toContain('BEGIN CERTIFICATE');
});
