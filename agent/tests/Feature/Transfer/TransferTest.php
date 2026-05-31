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

it('prevents seeing another device transfer (IDOR → 404)', function () {
    [$owner] = approvedDeviceWithToken();
    [$other, $otherToken] = approvedDeviceWithToken();
    $transfer = app(TransferService::class)->initiate($owner, Transfer::TO_PC, 'secret.txt', 10);

    $this->withHeaders(deviceHeaders($other->id, $otherToken))
        ->getJson("/api/transfers/{$transfer->id}")
        ->assertStatus(404);
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
