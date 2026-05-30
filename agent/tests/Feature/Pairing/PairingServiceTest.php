<?php

use App\Services\Crypto\KeyManager;
use App\Services\Pairing\PairingService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;

uses(RefreshDatabase::class);

function makePairingService(): PairingService
{
    // KeyManager pointe vers un dossier temporaire pour ne pas polluer $HOME
    $home = sys_get_temp_dir() . '/linkup-pairing-test-' . bin2hex(random_bytes(4));
    return new PairingService(new KeyManager(homeDir: $home));
}

it('creates an OTP with a unique base64url token', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    expect($otp->token)
        ->toBeString()
        ->toMatch('/^[A-Za-z0-9_\-]+$/'); // base64url, pas de + / =
    expect(strlen($otp->token))->toBeGreaterThanOrEqual(40);
    expect($otp->id)->toBeGreaterThan(0);
});

it('persists OTP in pairing_otps table', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    expect(DB::table('pairing_otps')->where('token', $otp->token)->exists())
        ->toBeTrue();
});

it('generates 100 unique OTP tokens without collision', function () {
    $service = makePairingService();
    $tokens = [];
    for ($i = 0; $i < 100; $i++) {
        $tokens[] = $service->createOtp()->token;
    }
    expect(count(array_unique($tokens)))->toBe(100);
});

it('consumeOtp returns true once then false (anti-replay)', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    expect($service->consumeOtp($otp->token))->toBeTrue();
    expect($service->consumeOtp($otp->token))->toBeFalse();
});

it('consumeOtp returns false for an expired token', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    // Simule l'expiration en mettant à jour expires_at dans le passé
    DB::table('pairing_otps')
        ->where('token', $otp->token)
        ->update(['expires_at' => now()->subMinute()]);

    expect($service->consumeOtp($otp->token))->toBeFalse();
});

it('consumeOtp returns false for an unknown token', function () {
    $service = makePairingService();
    expect($service->consumeOtp('definitely-not-a-real-token'))->toBeFalse();
});

it('purgeExpired deletes OTPs older than the purge window', function () {
    $service = makePairingService();
    $otp1 = $service->createOtp();
    $otp2 = $service->createOtp();

    // otp1 : vieux de 10 min → doit être purgé
    DB::table('pairing_otps')
        ->where('token', $otp1->token)
        ->update(['expires_at' => now()->subMinutes(10)]);
    // otp2 : juste expiré (vieux d'1 min) → pas encore purgé (PURGE_AFTER_SECONDS = 5min)
    DB::table('pairing_otps')
        ->where('token', $otp2->token)
        ->update(['expires_at' => now()->subMinute()]);

    $deleted = $service->purgeExpired();

    expect($deleted)->toBe(1);
    expect(DB::table('pairing_otps')->where('token', $otp1->token)->exists())->toBeFalse();
    expect(DB::table('pairing_otps')->where('token', $otp2->token)->exists())->toBeTrue();
});

it('builds a valid linkup:// pairing URL', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    $url = $service->buildPairingUrl('192.168.1.42', 8000, $otp->token);

    expect($url)
        ->toStartWith('linkup://192.168.1.42:8000?')
        ->toContain('pk=')
        ->toContain('otp=')
        ->toContain('&v=1');
});

it('URL-encodes both pk and otp safely', function () {
    $service = makePairingService();
    $otp = $service->createOtp();
    $url = $service->buildPairingUrl('10.0.0.1', 8000, $otp->token);

    // Parsing manuel pour valider que les params sont retrouvables
    $parts = parse_url($url);
    parse_str($parts['query'], $params);

    expect($params['otp'])->toBe($otp->token);
    expect($params['v'])->toBe('1');
    expect($params['pk'])->not->toBeEmpty();
});

it('exposes ttlSeconds on the DTO', function () {
    $service = makePairingService();
    $otp = $service->createOtp();

    expect($otp->ttlSeconds())
        ->toBeGreaterThan(50)
        ->toBeLessThanOrEqual(PairingService::OTP_TTL_SECONDS);
});
