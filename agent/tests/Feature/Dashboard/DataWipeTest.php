<?php

use App\Models\ClipboardEntry;
use App\Models\Device;
use App\Models\DeviceToken;
use App\Models\Transfer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

uses(RefreshDatabase::class);

/**
 * Réinitialisation du PC : efface fichiers reçus, transferts, presse-papier et
 * pairing. L'aperçu (summary) alimente l'écran de confirmation du dashboard.
 */

function dashboardHeadersData(): array
{
    return ['X-Linkup-Client' => 'dashboard'];
}

/** Crée un device + un fichier reçu réel sur le disque (inbox temporaire). */
function seedReceivedData(string $inbox): Device
{
    @mkdir($inbox . '/photos', 0700, true);
    file_put_contents($inbox . '/photos/IMG.jpg', 'binarydata');

    $device = Device::create([
        'name' => 'Pixel',
        'public_key' => base64_encode(random_bytes(32)),
        'fingerprint_sha256' => substr(hash('sha256', 'k'), 0, 8),
        'approved' => true,
        'paired_at' => now(),
        'approved_at' => now(),
    ]);
    DeviceToken::create([
        'device_id' => $device->id,
        'token_hash' => Hash::driver('argon2id')->make('tok'),
    ]);
    Transfer::create([
        'device_id' => $device->id,
        'filename' => 'IMG.jpg',
        'stored_name' => 'photos/IMG.jpg',
        'size' => 10,
        'direction' => Transfer::TO_PC,
        'status' => Transfer::COMPLETED,
        'completed_at' => now(),
    ]);
    ClipboardEntry::create([
        'device_id' => $device->id,
        'content' => 'copié depuis le tél',
        'hash' => hash('sha256', 'copié depuis le tél'),
        'origin' => 'phone',
    ]);
    DB::table('pairing_otps')->insert([
        'token' => 'otp-123',
        'expires_at' => now()->addMinutes(2),
        'created_at' => now(),
        'updated_at' => now(),
    ]);

    return $device;
}

it('blocks the reset routes without the dashboard header (403)', function () {
    $this->getJson('/api/data/summary')->assertStatus(403);
    $this->deleteJson('/api/data')->assertStatus(403);
});

it('summarises what will be deleted', function () {
    $inbox = sys_get_temp_dir() . '/linkup-wipe-' . uniqid();
    config(['services.linkup.inbox' => $inbox]);
    seedReceivedData($inbox);

    $this->withHeaders(dashboardHeadersData())->getJson('/api/data/summary')
        ->assertOk()
        ->assertJsonPath('files', 1)
        ->assertJsonPath('bytes', 10)
        ->assertJsonPath('clipboard', 1)
        ->assertJsonPath('devices', 1);
});

it('wipes everything: files on disk, transfers, clipboard and pairing', function () {
    $inbox = sys_get_temp_dir() . '/linkup-wipe-' . uniqid();
    config(['services.linkup.inbox' => $inbox]);
    seedReceivedData($inbox);

    expect(file_exists($inbox . '/photos/IMG.jpg'))->toBeTrue();

    $this->withHeaders(dashboardHeadersData())->deleteJson('/api/data')
        ->assertOk()
        ->assertJsonPath('deleted.files', 1)
        ->assertJsonPath('deleted.devices', 1);

    // Disque + toutes les tables vidées.
    expect(file_exists($inbox . '/photos/IMG.jpg'))->toBeFalse();
    expect(Transfer::count())->toBe(0);
    expect(Device::count())->toBe(0);
    expect(DeviceToken::count())->toBe(0);
    expect(ClipboardEntry::count())->toBe(0);
    expect(DB::table('pairing_otps')->count())->toBe(0);
});

it('is a no-op on an already-empty PC', function () {
    $this->withHeaders(dashboardHeadersData())->deleteJson('/api/data')
        ->assertOk()
        ->assertJsonPath('deleted.files', 0)
        ->assertJsonPath('deleted.devices', 0);
});
