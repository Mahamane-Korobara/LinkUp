<?php

use App\Services\Crypto\KeyManager;

/**
 * Tests S2.J1 — génération + persistance des paires Ed25519.
 */

function makeManager(): KeyManager
{
    $dir = sys_get_temp_dir() . '/linkup-test-' . bin2hex(random_bytes(6));
    return new KeyManager(homeDir: $dir);
}

it('generates and stores an Ed25519 keypair', function () {
    $manager = makeManager();
    $kp = $manager->ensureKeyPair();

    expect($kp)
        ->toHaveKey('public')
        ->toHaveKey('secret');
    // strlen() force le comptage en BYTES (mb_strlen lirait des caractères UTF-8
    // sur du binaire → résultat différent).
    expect(strlen(base64_decode($kp['public'])))->toBe(SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES);
    expect(strlen(base64_decode($kp['secret'])))->toBe(SODIUM_CRYPTO_SIGN_SECRETKEYBYTES);
});

it('persists the keypair and loads the same one back', function () {
    $manager = makeManager();
    $first = $manager->ensureKeyPair();
    $second = $manager->ensureKeyPair();

    expect($second['public'])->toBe($first['public']);
    expect($second['secret'])->toBe($first['secret']);
});

it('writes the secret key with chmod 600', function () {
    $manager = makeManager();
    $manager->ensureKeyPair();

    // On lit via reflection le chemin du fichier
    $ref = new ReflectionClass($manager);
    $home = $ref->getProperty('homeDir');
    $home->setAccessible(true);
    $secPath = $home->getValue($manager) . '/.linkup/keys/agent_ed25519.sec';

    expect(file_exists($secPath))->toBeTrue();
    $perms = fileperms($secPath) & 0777;
    expect($perms)->toBe(0600);
});

it('generates 100 unique keypairs without collision', function () {
    $publics = [];
    for ($i = 0; $i < 100; $i++) {
        $manager = makeManager();
        $publics[] = $manager->ensureKeyPair()['public'];
    }
    expect(count(array_unique($publics)))->toBe(100);
});

it('signs a message and verifies the signature', function () {
    $manager = makeManager();
    $message = 'hello-linkup';
    $signature = $manager->sign($message);

    $verified = $manager->verify($message, $signature, $manager->publicKey());
    expect($verified)->toBeTrue();
});

it('rejects a tampered message', function () {
    $manager = makeManager();
    $signature = $manager->sign('original');

    $verified = $manager->verify('tampered', $signature, $manager->publicKey());
    expect($verified)->toBeFalse();
});

it('rejects a signature from another keypair', function () {
    $alice = makeManager();
    $bob = makeManager();

    $signature = $alice->sign('hello');
    $verifiedByBob = $bob->verify('hello', $signature, $bob->publicKey());
    expect($verifiedByBob)->toBeFalse();
});

it('produces a stable 8-char hex fingerprint', function () {
    $manager = makeManager();
    $fp1 = $manager->fingerprint();
    $fp2 = $manager->fingerprint();

    expect($fp1)->toBe($fp2);
    expect($fp1)->toMatch('/^[0-9a-f]{8}$/');
});

it('reports exists() correctly before and after generation', function () {
    $manager = makeManager();
    expect($manager->exists())->toBeFalse();

    $manager->ensureKeyPair();
    expect($manager->exists())->toBeTrue();
});

it('does NOT regenerate if a keypair already exists on disk', function () {
    $dir = sys_get_temp_dir() . '/linkup-persistence-' . bin2hex(random_bytes(6));

    $manager1 = new KeyManager(homeDir: $dir);
    $first = $manager1->ensureKeyPair();

    // Nouvelle instance, même dossier → doit relire la même paire
    $manager2 = new KeyManager(homeDir: $dir);
    $second = $manager2->ensureKeyPair();

    expect($second['public'])->toBe($first['public']);
});
