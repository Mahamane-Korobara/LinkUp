<?php

use App\Events\ClipboardUpdated;
use App\Models\ClipboardEntry;
use App\Models\Device;
use App\Services\Clipboard\ClipboardService;
use App\Services\Pairing\DeviceApprovalService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Http;

uses(RefreshDatabase::class);

/** Device approuvé + token clair (helper nommé pour ne pas collisionner avec TransferTest). */
function clipApprovedDevice(): array
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

function clipHeaders(string $deviceId, string $token): array
{
    return ['X-Device-Id' => $deviceId, 'Authorization' => "Bearer {$token}"];
}

it('pushes phone clipboard to the PC and logs it', function () {
    Http::fake(['http://127.0.0.1:8765/clipboard/write' => Http::response(['ok' => true], 200)]);
    Event::fake([ClipboardUpdated::class]);
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/clipboard', ['content' => 'hello PC'])
        ->assertOk()
        ->assertJsonPath('ok', true);

    expect(ClipboardEntry::where('content', 'hello PC')->where('origin', 'phone')->exists())->toBeTrue();
    Http::assertSent(fn ($req) => $req->url() === 'http://127.0.0.1:8765/clipboard/write'
        && $req['text'] === 'hello PC');
    Event::assertDispatched(ClipboardUpdated::class);
});

it('dedups a clipboard push identical to the last entry (anti-loop)', function () {
    Http::fake(['http://127.0.0.1:8765/clipboard/write' => Http::response(['ok' => true], 200)]);
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/clipboard', ['content' => 'same'])
        ->assertOk();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/clipboard', ['content' => 'same'])
        ->assertOk()
        ->assertJsonPath('deduped', true);

    expect(ClipboardEntry::where('content', 'same')->count())->toBe(1);
});

it('reads the PC clipboard for the phone', function () {
    Http::fake(['http://127.0.0.1:8765/clipboard/read' => Http::response(['text' => 'from PC'], 200)]);
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->getJson('/api/clipboard/pc')
        ->assertOk()
        ->assertJsonPath('text', 'from PC');

    expect(ClipboardEntry::where('content', 'from PC')->where('origin', 'pc')->exists())->toBeTrue();
});

it('lists recent clipboard history for the device only', function () {
    [$device, $token] = clipApprovedDevice();
    [$other] = clipApprovedDevice();
    $service = app(ClipboardService::class);
    $service->receive($device, 'one', ClipboardService::ORIGIN_PHONE);
    $service->receive($device, 'two', ClipboardService::ORIGIN_PHONE);
    $service->receive($other, 'secret', ClipboardService::ORIGIN_PHONE);

    $this->withHeaders(clipHeaders($device->id, $token))
        ->getJson('/api/clipboard')
        ->assertOk()
        ->assertJsonCount(2, 'items')
        ->assertJsonMissing(['content' => 'secret']);
});

it('opens an http(s) link on the PC', function () {
    Http::fake(['http://127.0.0.1:8765/link/open' => Http::response(['ok' => true, 'url' => 'https://x.com'], 200)]);
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/link/open', ['url' => 'https://x.com'])
        ->assertOk()
        ->assertJsonPath('ok', true);

    Http::assertSent(fn ($req) => $req->url() === 'http://127.0.0.1:8765/link/open'
        && $req['url'] === 'https://x.com');
});

it('rejects a non-http link (422) and never reaches the bridge', function () {
    Http::fake();
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/link/open', ['url' => 'file:///etc/passwd'])
        ->assertStatus(422);

    Http::assertNothingSent();
});

it('requires device auth for clipboard endpoints (401)', function () {
    $this->postJson('/api/clipboard', ['content' => 'x'])->assertStatus(401);
    $this->getJson('/api/clipboard')->assertStatus(401);
    $this->postJson('/api/link/open', ['url' => 'https://x.com'])->assertStatus(401);
});

it('surfaces the bridge error and logs nothing when the PC write fails', function () {
    // Le bridge renvoie 422 « aucun outil » → Laravel relaie CE message en 503
    // et ne journalise AUCUNE entrée fantôme (write-then-log).
    Http::fake([
        'http://127.0.0.1:8765/clipboard/write' => Http::response(
            ['detail' => 'Aucun outil presse-papier trouvé. Installe wl-clipboard.'],
            422,
        ),
    ]);
    [$device, $token] = clipApprovedDevice();

    $this->withHeaders(clipHeaders($device->id, $token))
        ->postJson('/api/clipboard', ['content' => 'boom'])
        ->assertStatus(503)
        ->assertJsonPath('message', 'Aucun outil presse-papier trouvé. Installe wl-clipboard.');

    expect(ClipboardEntry::where('content', 'boom')->exists())->toBeFalse();
});

it('does not duplicate when the same PC clipboard is pulled repeatedly (auto poll)', function () {
    // Reproduit le bug : en mode auto, le tél tire le presse-papier du PC toutes
    // les ~3s ; le contenu ne change pas → on ne doit PAS empiler des doublons.
    Http::fake(['http://127.0.0.1:8765/clipboard/read' => Http::response(['text' => 'inchangé'], 200)]);
    [$device, $token] = clipApprovedDevice();

    for ($i = 0; $i < 4; $i++) {
        $this->withHeaders(clipHeaders($device->id, $token))
            ->getJson('/api/clipboard/pc')
            ->assertOk();
    }

    expect(ClipboardEntry::where('content', 'inchangé')->count())->toBe(1);
});

it('prunes clipboard entries older than the 2-day retention', function () {
    [$device] = clipApprovedDevice();
    $svc = app(ClipboardService::class);

    // Entrée vieille de 3 jours (au-delà de la rétention) + une fraîche.
    $old = ClipboardEntry::create([
        'device_id' => $device->id, 'content' => 'vieux', 'hash' => hash('sha256', 'vieux'), 'origin' => 'phone',
    ]);
    $old->forceFill(['created_at' => now()->subDays(3)])->save();
    ClipboardEntry::create([
        'device_id' => $device->id, 'content' => 'frais', 'hash' => hash('sha256', 'frais'), 'origin' => 'phone',
    ]);

    expect($svc->prune())->toBe(1);
    expect(ClipboardEntry::where('content', 'vieux')->exists())->toBeFalse();
    expect(ClipboardEntry::where('content', 'frais')->exists())->toBeTrue();
});

it('hides expired entries from the history even before pruning', function () {
    [$device] = clipApprovedDevice();
    $old = ClipboardEntry::create([
        'device_id' => $device->id, 'content' => 'expiré', 'hash' => hash('sha256', 'expiré'), 'origin' => 'pc',
    ]);
    $old->forceFill(['created_at' => now()->subDays(3)])->save();

    $recent = app(ClipboardService::class)->recent($device);
    expect($recent->pluck('content'))->not->toContain('expiré');
});

it('runs the scheduled prune command', function () {
    [$device] = clipApprovedDevice();
    $old = ClipboardEntry::create([
        'device_id' => $device->id, 'content' => 'old', 'hash' => hash('sha256', 'old'), 'origin' => 'phone',
    ]);
    $old->forceFill(['created_at' => now()->subDays(5)])->save();

    $this->artisan('linkup:prune-clipboard')->assertOk();
    expect(ClipboardEntry::count())->toBe(0);
});
