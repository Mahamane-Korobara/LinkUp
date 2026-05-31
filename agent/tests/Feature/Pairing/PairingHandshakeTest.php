<?php

use App\Events\PairingPendingApproval;
use App\Models\Device;
use App\Services\Crypto\KeyManager;
use App\Services\Pairing\PairingService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;

uses(RefreshDatabase::class);

/**
 * Tests S2.J3 — endpoint POST /api/pairing/handshake.
 * Simule un tel : génère une paire Ed25519, signe (otp || pubkey), POST,
 * vérifie la réponse + le Device persisté.
 */

function fakeTelKeyPair(): array
{
    $kp = sodium_crypto_sign_keypair();
    return [
        'public' => base64_encode(sodium_crypto_sign_publickey($kp)),
        'secret' => sodium_crypto_sign_secretkey($kp),
    ];
}

function signOtpAndPubkey(string $otp, string $pubB64, string $secret): string
{
    $message = $otp . $pubB64;
    return base64_encode(sodium_crypto_sign_detached($message, $secret));
}

function freshOtp(): string
{
    return app(PairingService::class)->createOtp()->token;
}

it('accepts a valid handshake and creates a pending Device', function () {
    Event::fake([PairingPendingApproval::class]);

    $tel = fakeTelKeyPair();
    $otp = freshOtp();
    $sig = signOtpAndPubkey($otp, $tel['public'], $tel['secret']);

    $response = $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp,
        'signature' => $sig,
        'device_name' => 'Samsung M15',
    ]);

    $response->assertOk()
        ->assertJsonStructure([
            'status',
            'device_id',
            'pc_public_key',
            'pc_fingerprint',
            'pc_name',
        ])
        ->assertJsonPath('status', 'pending_approval');

    expect(Device::where('public_key', $tel['public'])->exists())->toBeTrue();
    $device = Device::where('public_key', $tel['public'])->first();
    expect($device->name)->toBe('Samsung M15');
    expect($device->approved)->toBeFalse();
    expect($device->fingerprint_sha256)->toMatch('/^[0-9a-f]{8}$/');

    Event::assertDispatched(PairingPendingApproval::class);
});

it('rejects a reused OTP (anti-replay)', function () {
    $tel = fakeTelKeyPair();
    $otp = freshOtp();
    $sig = signOtpAndPubkey($otp, $tel['public'], $tel['secret']);

    // 1er handshake OK
    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp,
        'signature' => $sig,
    ])->assertOk();

    // 2e handshake avec MÊME OTP → refusé
    $tel2 = fakeTelKeyPair();
    $sig2 = signOtpAndPubkey($otp, $tel2['public'], $tel2['secret']);
    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel2['public'],
        'otp' => $otp,
        'signature' => $sig2,
    ])
        ->assertStatus(422)
        ->assertJsonPath('reason_code', 'otp_invalid');
});

it('rejects an unknown OTP', function () {
    $tel = fakeTelKeyPair();
    $fakeOtp = 'definitely-not-a-real-otp-token';
    $sig = signOtpAndPubkey($fakeOtp, $tel['public'], $tel['secret']);

    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $fakeOtp,
        'signature' => $sig,
    ])
        ->assertStatus(422)
        ->assertJsonPath('reason_code', 'otp_invalid');
});

it('rejects an expired OTP', function () {
    $tel = fakeTelKeyPair();
    $otp = freshOtp();

    // simule expiration
    \DB::table('pairing_otps')
        ->where('token', $otp)
        ->update(['expires_at' => now()->subMinute()]);

    $sig = signOtpAndPubkey($otp, $tel['public'], $tel['secret']);

    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp,
        'signature' => $sig,
    ])
        ->assertStatus(422)
        ->assertJsonPath('reason_code', 'otp_invalid');
});

it('rejects a forged signature (wrong secret key)', function () {
    $tel = fakeTelKeyPair();
    $otherTel = fakeTelKeyPair();
    $otp = freshOtp();

    // Signature avec la clé d'un AUTRE tel
    $sig = signOtpAndPubkey($otp, $tel['public'], $otherTel['secret']);

    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp,
        'signature' => $sig,
    ])
        ->assertStatus(422)
        ->assertJsonPath('reason_code', 'signature_invalid');
});

it('rejects a malformed public key', function () {
    $otp = freshOtp();
    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => base64_encode('too-short'),
        'otp' => $otp,
        'signature' => base64_encode(random_bytes(64)),
    ])
        ->assertStatus(422)
        ->assertJsonPath('reason_code', 'public_key_invalid');
});

it('does NOT create a duplicate device on re-pairing the same key', function () {
    $tel = fakeTelKeyPair();

    // 1er pairing
    $otp1 = freshOtp();
    $sig1 = signOtpAndPubkey($otp1, $tel['public'], $tel['secret']);
    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp1,
        'signature' => $sig1,
    ])->assertOk();

    // 2e pairing même tel
    $otp2 = freshOtp();
    $sig2 = signOtpAndPubkey($otp2, $tel['public'], $tel['secret']);
    $this->postJson('/api/pairing/handshake', [
        'tel_public_key' => $tel['public'],
        'otp' => $otp2,
        'signature' => $sig2,
    ])->assertOk();

    expect(Device::where('public_key', $tel['public'])->count())->toBe(1);
});

it('rejects missing fields', function () {
    $this->postJson('/api/pairing/handshake', [])
        ->assertStatus(422);
});
