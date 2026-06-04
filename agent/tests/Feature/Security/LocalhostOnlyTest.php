<?php

use App\Models\Device;
use App\Models\SecurityAudit;
use App\Models\Transfer;
use App\Services\Transfer\TransferService;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/** Variables serveur simulant un hôte du LAN (IP non-loopback). */
function lanServer(): array
{
    return ['REMOTE_ADDR' => '192.168.1.50'];
}

function localDevice(): Device
{
    $kp = sodium_crypto_sign_keypair();
    $pub = base64_encode(sodium_crypto_sign_publickey($kp));

    return Device::create([
        'name' => 'Phone',
        'public_key' => $pub,
        'fingerprint_sha256' => substr(hash('sha256', base64_decode($pub)), 0, 8),
        'approved' => true,
        'approved_at' => now(),
        'paired_at' => now(),
    ]);
}

it('blocks a dashboard management route from a LAN client even with the forged header', function () {
    // Header forgé MAIS IP LAN → 403 : le header statique ne suffit plus.
    $this->withServerVariables(lanServer())
        ->withHeaders(['X-Linkup-Client' => 'dashboard'])
        ->getJson('/api/pairing/devices')
        ->assertStatus(403)
        ->assertJsonPath('message', 'Réservé au PC local (origine non-loopback).');

    expect(SecurityAudit::where('event', 'non_local_forbidden')->count())->toBe(1);
});

it('blocks the public raw preview from a LAN client but serves it on loopback', function () {
    $inbox = sys_get_temp_dir() . '/linkup-raw-' . bin2hex(random_bytes(4));
    mkdir("$inbox/photos", 0700, true);
    file_put_contents("$inbox/photos/p.jpg", 'SECRETBYTES');
    config(['services.linkup.inbox' => $inbox]);

    $device = localDevice();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'p.jpg', 11, null, 1);
    app(TransferService::class)->complete($t, 'photos/p.jpg');

    // <img> du dashboard local (loopback par défaut) → servi.
    // NB : on teste la loopback EN PREMIER car withServerVariables() est sticky.
    $res = $this->get("/api/files/{$t->id}/raw")->assertOk();
    expect($res->streamedContent())->toBe('SECRETBYTES');

    // Hôte du LAN (curl) connaissant l'UUID → refusé (anti-exfiltration).
    $this->withServerVariables(lanServer())
        ->get("/api/files/{$t->id}/raw")
        ->assertStatus(403);

    @unlink("$inbox/photos/p.jpg");
    @rmdir("$inbox/photos");
    @rmdir($inbox);
});

it('treats the 127.0.0.0/8 range as loopback (e.g. 127.0.1.1)', function () {
    localDevice();
    $this->withServerVariables(['REMOTE_ADDR' => '127.0.1.1'])
        ->withHeaders(['X-Linkup-Client' => 'dashboard'])
        ->getJson('/api/pairing/devices')
        ->assertOk();
});
