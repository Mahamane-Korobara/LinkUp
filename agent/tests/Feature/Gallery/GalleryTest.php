<?php

use App\Models\Device;
use App\Models\GalleryItem;
use App\Services\Pairing\DeviceApprovalService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;

uses(RefreshDatabase::class);

function galleryDevice(): array
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

function galleryHeaders(string $deviceId, string $token): array
{
    return ['X-Device-Id' => $deviceId, 'Authorization' => "Bearer {$token}"];
}

function dashHeaders(): array
{
    return ['Accept' => 'application/json', 'X-Linkup-Client' => 'dashboard'];
}

/**
 * Variables serveur pour un POST /gallery/thumb à corps brut : `call()` (le seul
 * moyen d'envoyer un body binaire) n'applique PAS `withHeaders()`, il faut donc
 * passer les en-têtes sous forme HTTP_*.
 */
function thumbServer(Device $device, string $token, string $mediaId): array
{
    return [
        'HTTP_X_DEVICE_ID' => $device->id,
        'HTTP_AUTHORIZATION' => "Bearer {$token}",
        'HTTP_X_MEDIA_ID' => $mediaId,
        'CONTENT_TYPE' => 'image/jpeg',
    ];
}

it('syncs gallery metadata and reports pending thumbnails', function () {
    [$device, $token] = galleryDevice();

    $res = $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson('/api/gallery/sync', ['items' => [
            ['media_id' => '100', 'mime' => 'image/jpeg', 'size' => 2048, 'taken_at' => '2026-05-01T10:00:00Z'],
            ['media_id' => '101', 'mime' => 'video/mp4', 'size' => 999999],
        ]])
        ->assertOk()
        ->assertJsonPath('ok', true);

    expect($res->json('pending_thumbs'))->toEqualCanonicalizing(['100', '101']);
    expect(GalleryItem::where('device_id', $device->id)->count())->toBe(2);
});

it('rejects a non-image/video mime (422)', function () {
    [$device, $token] = galleryDevice();

    $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson('/api/gallery/sync', ['items' => [
            ['media_id' => '1', 'mime' => 'application/pdf', 'size' => 1],
        ]])
        ->assertStatus(422);
});

it('is idempotent on (device, media_id)', function () {
    [$device, $token] = galleryDevice();
    $payload = ['items' => [['media_id' => '100', 'mime' => 'image/jpeg', 'size' => 10]]];

    $this->withHeaders(galleryHeaders($device->id, $token))->postJson('/api/gallery/sync', $payload)->assertOk();
    $this->withHeaders(galleryHeaders($device->id, $token))->postJson('/api/gallery/sync', $payload)->assertOk();

    expect(GalleryItem::count())->toBe(1);
});

it('uploads a thumbnail, stores it and clears it from pending', function () {
    Storage::fake('local');
    [$device, $token] = galleryDevice();
    $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson('/api/gallery/sync', ['items' => [['media_id' => '100', 'mime' => 'image/jpeg', 'size' => 10]]]);

    $this->call('POST', '/api/gallery/thumb', [], [], [], thumbServer($device, $token, '100'), 'JPEGBYTES')
        ->assertOk();

    expect(GalleryItem::where('media_id', '100')->first()->has_thumb)->toBeTrue();
    Storage::disk('local')->assertExists('gallery/' . $device->id . '/' . sha1('100') . '.jpg');

    // plus dans pending au prochain sync
    $res = $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson('/api/gallery/sync', ['items' => [['media_id' => '100', 'mime' => 'image/jpeg', 'size' => 10]]]);
    expect($res->json('pending_thumbs'))->toBe([]);
});

it('refuses a thumbnail for an unknown media (404)', function () {
    [$device, $token] = galleryDevice();

    $this->call('POST', '/api/gallery/thumb', [], [], [], thumbServer($device, $token, 'ghost'), 'JPEGBYTES')
        ->assertStatus(404);
});

it('lists the gallery for the dashboard (recent first) and serves thumbnails', function () {
    Storage::fake('local');
    [$device, $token] = galleryDevice();
    $this->withHeaders(galleryHeaders($device->id, $token))->postJson('/api/gallery/sync', ['items' => [
        ['media_id' => 'old', 'mime' => 'image/jpeg', 'size' => 1, 'taken_at' => '2026-01-01T00:00:00Z'],
        ['media_id' => 'new', 'mime' => 'image/jpeg', 'size' => 1, 'taken_at' => '2026-05-01T00:00:00Z'],
    ]]);
    $this->call('POST', '/api/gallery/thumb', [], [], [], thumbServer($device, $token, 'new'), 'IMG');

    $list = $this->withHeaders(dashHeaders())->getJson('/api/gallery')
        ->assertOk()
        ->assertJsonPath('total', 2)
        ->assertJsonPath('items.0.media_id', 'new'); // récent d'abord

    expect($list->json('items.0.has_thumb'))->toBeTrue();
    $newId = $list->json('items.0.id');

    $this->withHeaders(dashHeaders())
        ->get("/api/gallery/{$newId}/thumb")
        ->assertOk()
        ->assertHeader('Content-Type', 'image/jpeg');
});

it('404 on thumbnail endpoint when none was uploaded', function () {
    [$device, $token] = galleryDevice();
    $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson('/api/gallery/sync', ['items' => [['media_id' => 'x', 'mime' => 'image/jpeg', 'size' => 1]]]);
    $id = GalleryItem::first()->id;

    $this->withHeaders(dashHeaders())->get("/api/gallery/{$id}/thumb")->assertStatus(404);
});

it('requires the right auth (device for sync, dashboard header for listing)', function () {
    $this->postJson('/api/gallery/sync', ['items' => []])->assertStatus(401);
    $this->getJson('/api/gallery')->assertStatus(403);
});
