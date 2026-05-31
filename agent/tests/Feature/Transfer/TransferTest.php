<?php

use App\Events\FileTransferRequested;
use App\Models\Device;
use App\Models\SecurityAudit;
use App\Models\Transfer;
use App\Services\Pairing\DeviceApprovalService;
use App\Services\Security\SecurityAuditService;
use App\Services\Transfer\TransferService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Http;

uses(RefreshDatabase::class);

/** Crée un device approuvé + son token clair (via le vrai service d'émission). */
function approvedDeviceWithToken(): array
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
    $token = app(DeviceApprovalService::class)->issueTokenOnce($device);

    return [$device, $token];
}

function deviceHeaders(string $deviceId, string $token): array
{
    return ['X-Device-Id' => $deviceId, 'Authorization' => "Bearer {$token}"];
}

it('GET /api/me confirms a still-valid pairing, 401 otherwise', function () {
    [$device, $token] = approvedDeviceWithToken();

    // Token valide → 200 + infos device (le tél sait qu'il est encore appairé).
    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson('/api/me')
        ->assertOk()
        ->assertJsonPath('device_id', $device->id)
        ->assertJsonPath('approved', true);

    // Device oublié côté PC (ex. migrate:fresh) → token invalide → 401.
    $device->delete();
    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson('/api/me')
        ->assertStatus(401);
});

it('initiates a transfer with a valid device token', function () {
    Event::fake([FileTransferRequested::class]);
    [$device, $token] = approvedDeviceWithToken();

    $response = $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson('/api/transfers', [
            'filename' => 'photo.jpg',
            'size' => 1024,
            'sha256' => str_repeat('a', 64),
            'direction' => 'to_pc',
            'total_chunks' => 2,
        ])
        ->assertCreated()
        ->assertJsonPath('status', 'pending')
        ->assertJsonPath('filename', 'photo.jpg')
        ->assertJsonPath('direction', 'to_pc')
        ->assertJsonStructure(['transfer_id', 'upload_token', 'bridge_port']);

    $transfer = Transfer::where('device_id', $device->id)->firstOrFail();
    // Le token d'upload renvoyé est bien le HMAC scopé à ce transfert.
    expect($response->json('upload_token'))
        ->toBe(app(\App\Services\Transfer\TransferTokenSigner::class)->sign($transfer->id));

    Event::assertDispatched(FileTransferRequested::class);
});

it('rejects a transfer without device auth (401) and audits it', function () {
    $this->postJson('/api/transfers', [
        'filename' => 'x.bin',
        'size' => 1,
        'direction' => 'to_pc',
    ])->assertStatus(401);

    expect(SecurityAudit::where('event', SecurityAuditService::DEVICE_AUTH_FAILED)->exists())
        ->toBeTrue();
    expect(Transfer::count())->toBe(0);
});

it('rejects a transfer with a wrong token (401)', function () {
    [$device] = approvedDeviceWithToken();

    $this->withHeaders(deviceHeaders($device->id, 'not-the-real-token'))
        ->postJson('/api/transfers', [
            'filename' => 'x.bin',
            'size' => 1,
            'direction' => 'to_pc',
        ])->assertStatus(401);
});

it('rejects a revoked device even with a valid token (401)', function () {
    [$device, $token] = approvedDeviceWithToken();
    $device->forceFill(['revoked_at' => now()])->save();

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson('/api/transfers', [
            'filename' => 'x.bin',
            'size' => 1,
            'direction' => 'to_pc',
        ])->assertStatus(401);
});

it('validates the direction', function () {
    [$device, $token] = approvedDeviceWithToken();

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson('/api/transfers', [
            'filename' => 'x.bin',
            'size' => 1,
            'direction' => 'sideways',
        ])->assertStatus(422);
});

it('shows a transfer status with received chunks (resume)', function () {
    [$device, $token] = approvedDeviceWithToken();
    $service = app(TransferService::class);
    $transfer = $service->initiate($device, Transfer::TO_PC, 'big.zip', 3000, null, 3);
    $service->recordChunk($transfer, 0, str_repeat('1', 64));
    $service->recordChunk($transfer, 2, str_repeat('2', 64));

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson("/api/transfers/{$transfer->id}")
        ->assertOk()
        ->assertJsonPath('status', 'uploading') // passé en uploading au 1er chunk
        ->assertJsonPath('received_chunks', [0, 2]);
});

it('lists only the calling device transfers, recent first', function () {
    [$owner, $token] = approvedDeviceWithToken();
    [$other] = approvedDeviceWithToken();
    $service = app(TransferService::class);

    $old = $service->initiate($owner, Transfer::TO_PC, 'old.txt', 10);
    $old->forceFill(['created_at' => now()->subMinutes(5)])->save();
    $recent = $service->initiate($owner, Transfer::TO_PC, 'recent.txt', 20);
    $service->initiate($other, Transfer::TO_PC, 'secret.txt', 30); // autre device

    $this->withHeaders(deviceHeaders($owner->id, $token))
        ->getJson('/api/transfers')
        ->assertOk()
        ->assertJsonCount(2, 'transfers')
        ->assertJsonPath('transfers.0.transfer_id', $recent->id) // récent d'abord
        ->assertJsonPath('transfers.1.transfer_id', $old->id)
        ->assertJsonMissing(['filename' => 'secret.txt']);
});

it('prevents seeing another device transfer (IDOR → 404)', function () {
    [$owner] = approvedDeviceWithToken();
    [$other, $otherToken] = approvedDeviceWithToken();
    $transfer = app(TransferService::class)->initiate($owner, Transfer::TO_PC, 'secret.txt', 10);

    $this->withHeaders(deviceHeaders($other->id, $otherToken))
        ->getJson("/api/transfers/{$transfer->id}")
        ->assertStatus(404);
});

it('marks a transfer completed when the phone confirms (fixes pending status)', function () {
    [$device, $token] = approvedDeviceWithToken();
    $transfer = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);
    expect($transfer->status)->toBe(Transfer::PENDING);

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson("/api/transfers/{$transfer->id}/complete", ['stored_name' => 'pic.jpg'])
        ->assertOk()
        ->assertJsonPath('status', 'completed');

    $fresh = $transfer->fresh();
    expect($fresh->status)->toBe(Transfer::COMPLETED);
    expect($fresh->completed_at)->not->toBeNull();
    expect($fresh->stored_name)->toBe('pic.jpg');
});

it('opens a completed transfer file on the PC via the bridge', function () {
    Http::fake(['http://127.0.0.1:8765/transfer/open' => Http::response(['ok' => true], 200)]);
    [$device, $token] = approvedDeviceWithToken();
    $transfer = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);
    app(TransferService::class)->complete($transfer, 'pic.jpg');

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson("/api/transfers/{$transfer->id}/open")
        ->assertOk()
        ->assertJsonPath('ok', true);

    Http::assertSent(fn ($req) => $req->url() === 'http://127.0.0.1:8765/transfer/open'
        && $req->header('X-Filename')[0] === 'pic.jpg');
});

it('downloads a completed transfer file from the inbox', function () {
    $inbox = sys_get_temp_dir() . '/linkup-inbox-' . bin2hex(random_bytes(4));
    mkdir($inbox, 0700, true);
    file_put_contents("$inbox/pic.jpg", 'IMAGEBYTES');
    config(['services.linkup.inbox' => $inbox]);

    [$device, $token] = approvedDeviceWithToken();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 10, null, 1);
    app(TransferService::class)->complete($t, 'pic.jpg');

    $res = $this->withHeaders(deviceHeaders($device->id, $token))
        ->get("/api/transfers/{$t->id}/download");
    $res->assertOk();
    expect($res->streamedContent())->toBe('IMAGEBYTES');

    @unlink("$inbox/pic.jpg");
    @rmdir($inbox);
});

it('refuses to download a not-completed transfer (409)', function () {
    [$device, $token] = approvedDeviceWithToken();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 10, null, 1);

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson("/api/transfers/{$t->id}/download")
        ->assertStatus(409);
});

it('prevents downloading another device file (IDOR → 404)', function () {
    [$owner] = approvedDeviceWithToken();
    [$other, $otherToken] = approvedDeviceWithToken();
    $t = app(TransferService::class)->initiate($owner, Transfer::TO_PC, 'pic.jpg', 10, null, 1);
    app(TransferService::class)->complete($t, 'pic.jpg');

    $this->withHeaders(deviceHeaders($other->id, $otherToken))
        ->getJson("/api/transfers/{$t->id}/download")
        ->assertStatus(404);
});

it('refuses to open a not-yet-completed transfer (409)', function () {
    [$device, $token] = approvedDeviceWithToken();
    $transfer = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);

    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson("/api/transfers/{$transfer->id}/open")
        ->assertStatus(409);
});

it('records chunks idempotently and transitions to terminal states', function () {
    [$device] = approvedDeviceWithToken();
    $service = app(TransferService::class);
    $transfer = $service->initiate($device, Transfer::TO_PC, 'f', 10, null, 1);

    $service->recordChunk($transfer, 0, str_repeat('a', 64));
    $service->recordChunk($transfer, 0, str_repeat('b', 64)); // même index → update
    expect($service->receivedChunkIndices($transfer))->toBe([0]);

    $service->complete($transfer);
    expect($transfer->fresh()->status)->toBe(Transfer::COMPLETED);

    // cancel sur un transfert terminal ne change rien
    $service->cancel($transfer);
    expect($transfer->fresh()->status)->toBe(Transfer::COMPLETED);
});
