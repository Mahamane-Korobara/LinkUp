<?php

use App\Events\DeviceApproved;
use App\Models\Device;
use App\Models\DeviceToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;

uses(RefreshDatabase::class);

/**
 * Tests S2.J4 — approbation / refus des devices + émission token (poll).
 */

function makeTelKeyPair(): array
{
    $kp = sodium_crypto_sign_keypair();
    return [
        'public' => base64_encode(sodium_crypto_sign_publickey($kp)),
        'secret' => sodium_crypto_sign_secretkey($kp),
    ];
}

function pendingDevice(?array $tel = null): array
{
    $tel ??= makeTelKeyPair();
    $device = Device::create([
        'name' => 'Test Phone',
        'public_key' => $tel['public'],
        'fingerprint_sha256' => substr(hash('sha256', base64_decode($tel['public'])), 0, 8),
        'approved' => false,
        'paired_at' => now(),
    ]);

    return [$device, $tel];
}

function signDeviceId(string $deviceId, string $secret): string
{
    return base64_encode(sodium_crypto_sign_detached($deviceId, $secret));
}

it('lists devices with their status', function () {
    [$pending] = pendingDevice();

    $this->getJson('/api/pairing/devices')
        ->assertOk()
        ->assertJsonPath('devices.0.device_id', $pending->id)
        ->assertJsonPath('devices.0.status', 'pending');
});

it('approves a pending device and broadcasts DeviceApproved', function () {
    Event::fake([DeviceApproved::class]);
    [$device] = pendingDevice();

    $this->postJson("/api/pairing/devices/{$device->id}/approve")
        ->assertOk()
        ->assertJsonPath('status', 'approved');

    expect($device->fresh()->approved)->toBeTrue();
    expect($device->fresh()->approved_at)->not->toBeNull();
    Event::assertDispatched(DeviceApproved::class);
});

it('rejects a device and marks it revoked', function () {
    [$device] = pendingDevice();

    $this->postJson("/api/pairing/devices/{$device->id}/reject")
        ->assertOk()
        ->assertJsonPath('status', 'rejected');

    expect($device->fresh()->revoked_at)->not->toBeNull();
    expect($device->fresh()->approved)->toBeFalse();
});

it('refuses to approve a revoked device (409)', function () {
    [$device] = pendingDevice();
    $device->forceFill(['revoked_at' => now()])->save();

    $this->postJson("/api/pairing/devices/{$device->id}/approve")
        ->assertStatus(409);
});

it('poll returns pending for a not-yet-approved device', function () {
    [$device, $tel] = pendingDevice();

    $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $tel['secret']),
    ])
        ->assertOk()
        ->assertJsonPath('status', 'pending')
        ->assertJsonMissingPath('token');
});

it('poll delivers the token exactly once after approval', function () {
    Event::fake([DeviceApproved::class]);
    [$device, $tel] = pendingDevice();
    $device->forceFill(['approved' => true, 'approved_at' => now()])->save();

    // 1er poll → token en clair
    $first = $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $tel['secret']),
    ])->assertOk()->assertJsonPath('status', 'approved');

    $token = $first->json('token');
    expect($token)->toBeString()->not->toBeEmpty();

    // Le hash stocké vérifie bien le token clair, et n'est PAS le token clair.
    $row = DeviceToken::where('device_id', $device->id)->firstOrFail();
    expect($row->token_hash)->not->toBe($token);
    expect(Hash::driver('argon2id')->check($token, $row->token_hash))->toBeTrue();

    // 2e poll → plus de token (déjà émis)
    $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $tel['secret']),
    ])->assertOk()->assertJsonPath('token', null);

    expect(DeviceToken::where('device_id', $device->id)->count())->toBe(1);
});

it('poll rejects a forged signature (403)', function () {
    [$device] = pendingDevice();
    $device->forceFill(['approved' => true, 'approved_at' => now()])->save();
    $attacker = makeTelKeyPair();

    $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $attacker['secret']),
    ])->assertStatus(403);

    expect(DeviceToken::where('device_id', $device->id)->exists())->toBeFalse();
});

it('poll returns rejected status for a revoked device', function () {
    [$device, $tel] = pendingDevice();
    $device->forceFill(['revoked_at' => now()])->save();

    $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $tel['secret']),
    ])
        ->assertOk()
        ->assertJsonPath('status', 'rejected');
});

it('poll returns 404 for an unknown device', function () {
    $tel = makeTelKeyPair();
    $this->postJson('/api/pairing/poll', [
        'device_id' => '00000000-0000-0000-0000-000000000000',
        'signature' => signDeviceId('whatever', $tel['secret']),
    ])->assertStatus(404);
});

it('auto-rejects a pending device older than the approval TTL on poll', function () {
    [$device, $tel] = pendingDevice();
    // Appairé il y a plus de 2 min sans approbation.
    $device->forceFill(['paired_at' => now()->subSeconds(121)])->save();

    $this->postJson('/api/pairing/poll', [
        'device_id' => $device->id,
        'signature' => signDeviceId($device->id, $tel['secret']),
    ])
        ->assertOk()
        ->assertJsonPath('status', 'rejected');

    expect($device->fresh()->revoked_at)->not->toBeNull();
});

it('auto-rejects stale pending devices when listing', function () {
    [$stale] = pendingDevice();
    $stale->forceFill(['paired_at' => now()->subSeconds(121)])->save();
    [$fresh] = pendingDevice();

    $this->getJson('/api/pairing/devices')->assertOk();

    expect($stale->fresh()->status())->toBe('rejected');
    expect($fresh->fresh()->status())->toBe('pending');
});
