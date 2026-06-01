<?php

use App\Models\Device;
use App\Models\Transfer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;

uses(RefreshDatabase::class);

/** Réutilise approvedDeviceWithToken() / deviceHeaders() de TransferTest.php. */
function outboxDashHeaders(): array
{
    return ['Accept' => 'application/json', 'X-Linkup-Client' => 'dashboard'];
}

beforeEach(function () {
    // Outbox isolé pour les tests (sinon ~/Linkup/Outbox réel).
    $dir = sys_get_temp_dir() . '/linkup-outbox-test-' . uniqid();
    config(['services.linkup.outbox' => $dir]);
});

it('lets the dashboard send a file to a phone, which then fetches it', function () {
    [$device, $token] = approvedDeviceWithToken();

    // 1. Dashboard dépose un fichier pour ce tél.
    $res = $this->withHeaders(outboxDashHeaders())
        ->post("/api/outbox/{$device->id}", [
            'file' => UploadedFile::fake()->createWithContent('vacances.jpg', 'IMGBYTES'),
        ])
        ->assertCreated()
        ->assertJsonPath('filename', 'vacances.jpg');

    $transferId = $res->json('transfer_id');
    expect(Transfer::find($transferId)->direction)->toBe(Transfer::TO_PHONE);

    // 2. Le tél voit le fichier dans ses entrants.
    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson('/api/transfers/incoming')
        ->assertOk()
        ->assertJsonPath('transfers.0.transfer_id', $transferId)
        ->assertJsonPath('transfers.0.direction', 'to_phone');

    // 3. Le tél télécharge les octets (servis depuis l'outbox, nom d'origine).
    $dl = $this->withHeaders(deviceHeaders($device->id, $token))
        ->get("/api/transfers/{$transferId}/download")
        ->assertOk();
    expect($dl->streamedContent())->toBe('IMGBYTES');

    // 4. Le tél confirme la remise → disparaît des entrants.
    $this->withHeaders(deviceHeaders($device->id, $token))
        ->postJson("/api/transfers/{$transferId}/delivered")
        ->assertOk();

    expect(Transfer::find($transferId)->status)->toBe(Transfer::DELIVERED);
    $this->withHeaders(deviceHeaders($device->id, $token))
        ->getJson('/api/transfers/incoming')
        ->assertJsonCount(0, 'transfers');
});

it('refuses to send to a non-approved device (403)', function () {
    $device = Device::create([
        'name' => 'NotApproved',
        'public_key' => base64_encode(str_repeat('x', 32)),
        'fingerprint_sha256' => 'deadbeef',
        'approved' => false,
    ]);

    $this->withHeaders(outboxDashHeaders())
        ->post("/api/outbox/{$device->id}", [
            'file' => UploadedFile::fake()->createWithContent('x.jpg', 'X'),
        ])
        ->assertStatus(403);
});

it('requires the dashboard header for outbox (no random web page)', function () {
    [$device] = approvedDeviceWithToken();

    $this->post("/api/outbox/{$device->id}", [
        'file' => UploadedFile::fake()->createWithContent('x.jpg', 'X'),
    ])->assertStatus(403);
});

it('prevents a phone from marking another phone delivery (404)', function () {
    [$deviceA] = approvedDeviceWithToken();
    [$deviceB, $tokenB] = approvedDeviceWithToken();

    $res = $this->withHeaders(outboxDashHeaders())
        ->post("/api/outbox/{$deviceA->id}", [
            'file' => UploadedFile::fake()->createWithContent('a.jpg', 'A'),
        ]);
    $transferId = $res->json('transfer_id');

    $this->withHeaders(deviceHeaders($deviceB->id, $tokenB))
        ->postJson("/api/transfers/{$transferId}/delivered")
        ->assertStatus(404);
});
