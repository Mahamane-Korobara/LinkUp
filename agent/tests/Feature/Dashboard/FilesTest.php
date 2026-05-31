<?php

use App\Models\Device;
use App\Models\Transfer;
use App\Services\Transfer\TransferService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;

uses(RefreshDatabase::class);

function approvedDevice(): Device
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

function dash(): array
{
    return ['X-Linkup-Client' => 'dashboard'];
}

it('lists only completed received files and requires the dashboard header', function () {
    $device = approvedDevice();
    $service = app(TransferService::class);
    $done = $service->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);
    $service->complete($done, 'pic.jpg');
    $service->initiate($device, Transfer::TO_PC, 'wip.bin', 50); // pending → exclu

    // Sans header dashboard → 403 (anti-CSRF).
    $this->getJson('/api/files')->assertStatus(403);

    $this->withHeaders(dash())->getJson('/api/files')
        ->assertOk()
        ->assertJsonCount(1, 'files')
        ->assertJsonPath('files.0.filename', 'pic.jpg')
        ->assertJsonPath('files.0.device', 'Phone');
});

it('opens a received file on the PC via the bridge', function () {
    Http::fake(['http://127.0.0.1:8765/transfer/open' => Http::response(['ok' => true], 200)]);
    $device = approvedDevice();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);
    app(TransferService::class)->complete($t, 'pic.jpg');

    $this->withHeaders(dash())->postJson("/api/files/{$t->id}/open")
        ->assertOk()
        ->assertJsonPath('ok', true);

    Http::assertSent(fn ($req) => $req->url() === 'http://127.0.0.1:8765/transfer/open'
        && $req->header('X-Filename')[0] === 'pic.jpg');
});
