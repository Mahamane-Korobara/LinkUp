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

it('exposes the media category derived from the stored subfolder', function () {
    $device = approvedDevice();
    $service = app(TransferService::class);

    $img = $service->initiate($device, Transfer::TO_PC, 'pic.jpg', 100, null, 1);
    $service->complete($img, 'photos/pic.jpg');
    $vid = $service->initiate($device, Transfer::TO_PC, 'clip.mp4', 100, null, 1);
    $service->complete($vid, 'video/clip.mp4');
    $doc = $service->initiate($device, Transfer::TO_PC, 'cv.pdf', 100, null, 1);
    $service->complete($doc, 'fichiers/cv.pdf');

    $files = $this->withHeaders(dash())->getJson('/api/files')->assertOk()->json('files');
    $byName = collect($files)->keyBy('filename');

    expect($byName['pic.jpg']['category'])->toBe('photos');
    expect($byName['clip.mp4']['category'])->toBe('video');
    expect($byName['cv.pdf']['category'])->toBe('fichiers');
});

it('serves the raw bytes of a received file for preview (subfolder path)', function () {
    $inbox = sys_get_temp_dir() . '/linkup-inbox-' . bin2hex(random_bytes(4));
    mkdir("$inbox/photos", 0700, true);
    file_put_contents("$inbox/photos/pic.jpg", 'IMAGEBYTES');
    config(['services.linkup.inbox' => $inbox]);

    $device = approvedDevice();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'pic.jpg', 10, null, 1);
    app(TransferService::class)->complete($t, 'photos/pic.jpg');

    // <img>/<video> n'envoient pas le header dashboard → la route doit rester
    // accessible SANS lui (lecture seule).
    $res = $this->get("/api/files/{$t->id}/raw");
    $res->assertOk();
    expect($res->streamedContent())->toBe('IMAGEBYTES');

    @unlink("$inbox/photos/pic.jpg");
    @rmdir("$inbox/photos");
    @rmdir($inbox);
});

it('serves raw bytes from the legacy flat inbox for pre-migration files', function () {
    // Nouvelle inbox VIDE + ancien dossier plat contenant le fichier.
    $newInbox = sys_get_temp_dir() . '/linkup-transfert-' . bin2hex(random_bytes(4));
    $legacy = sys_get_temp_dir() . '/linkup-legacy-' . bin2hex(random_bytes(4));
    mkdir($newInbox, 0700, true);
    mkdir($legacy, 0700, true);
    file_put_contents("$legacy/old.jpg", 'OLDBYTES');
    config(['services.linkup.inbox' => $newInbox, 'services.linkup.inbox_legacy' => $legacy]);

    $device = approvedDevice();
    $t = app(TransferService::class)->initiate($device, Transfer::TO_PC, 'old.jpg', 8, null, 1);
    // stored_name « moderne » (relpath) mais fichier réellement dans le legacy.
    app(TransferService::class)->complete($t, 'photos/old.jpg');

    $res = $this->get("/api/files/{$t->id}/raw");
    $res->assertOk();
    expect($res->streamedContent())->toBe('OLDBYTES');

    @unlink("$legacy/old.jpg");
    @rmdir($legacy);
    @rmdir($newInbox);
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
