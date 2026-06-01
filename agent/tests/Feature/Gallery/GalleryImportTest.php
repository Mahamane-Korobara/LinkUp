<?php

use App\Models\Device;
use App\Models\GalleryImportRequest;
use App\Models\GalleryItem;
use App\Services\Pairing\DeviceApprovalService;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

/** Réutilise les helpers définis dans GalleryTest.php (même suite Pest). */
function importedItem(Device $device, string $mediaId = '100'): GalleryItem
{
    return GalleryItem::create([
        'device_id' => $device->id,
        'media_id' => $mediaId,
        'mime' => 'image/jpeg',
        'size' => 2048,
    ]);
}

it('lets the dashboard request an import and the phone poll it', function () {
    [$device, $token] = galleryDevice();
    $item = importedItem($device);

    // Dashboard demande l'import.
    $this->withHeaders(dashHeaders())
        ->postJson('/api/gallery/import', ['ids' => [$item->id]])
        ->assertOk()
        ->assertJsonPath('requested', 1);

    expect(GalleryImportRequest::where('gallery_item_id', $item->id)->value('status'))
        ->toBe(GalleryImportRequest::REQUESTED);

    // Le tél récupère la demande en attente.
    $res = $this->withHeaders(galleryHeaders($device->id, $token))
        ->getJson('/api/gallery/imports')
        ->assertOk();

    expect($res->json('imports'))->toHaveCount(1);
    expect($res->json('imports.0.media_id'))->toBe('100');
    expect($res->json('imports.0.mime'))->toBe('image/jpeg');
});

it('marks an import done and points to the transfer', function () {
    [$device, $token] = galleryDevice();
    $item = importedItem($device);
    $this->withHeaders(dashHeaders())->postJson('/api/gallery/import', ['ids' => [$item->id]]);
    $importId = GalleryImportRequest::first()->id;

    $this->withHeaders(galleryHeaders($device->id, $token))
        ->postJson("/api/gallery/imports/{$importId}/done", ['transfer_id' => 'tx-123'])
        ->assertOk()
        ->assertJsonPath('ok', true);

    $req = GalleryImportRequest::find($importId);
    expect($req->status)->toBe(GalleryImportRequest::DONE);
    expect($req->transfer_id)->toBe('tx-123');

    // N'apparaît plus dans les demandes en attente.
    $this->withHeaders(galleryHeaders($device->id, $token))
        ->getJson('/api/gallery/imports')
        ->assertJsonCount(0, 'imports');
});

it('exposes import_status in the dashboard listing', function () {
    [$device, $token] = galleryDevice();
    $item = importedItem($device);
    $this->withHeaders(dashHeaders())->postJson('/api/gallery/import', ['ids' => [$item->id]]);

    $this->withHeaders(dashHeaders())->getJson('/api/gallery')
        ->assertOk()
        ->assertJsonPath('items.0.import_status', 'requested');
});

it('prevents a device from marking another device import (404)', function () {
    [$deviceA] = galleryDevice();
    [$deviceB, $tokenB] = galleryDevice();
    $item = importedItem($deviceA);
    $this->withHeaders(dashHeaders())->postJson('/api/gallery/import', ['ids' => [$item->id]]);
    $importId = GalleryImportRequest::first()->id;

    // B (autre device) tente de marquer la demande de A → 404 anti-IDOR.
    $this->withHeaders(galleryHeaders($deviceB->id, $tokenB))
        ->postJson("/api/gallery/imports/{$importId}/done", [])
        ->assertStatus(404);

    expect(GalleryImportRequest::find($importId)->status)->toBe(GalleryImportRequest::REQUESTED);
});

it('re-requesting an already imported item resets it to requested', function () {
    [$device] = galleryDevice();
    $item = importedItem($device);
    $req = GalleryImportRequest::create([
        'device_id' => $device->id,
        'gallery_item_id' => $item->id,
        'media_id' => $item->media_id,
        'status' => GalleryImportRequest::DONE,
        'transfer_id' => 'old-tx',
    ]);

    $this->withHeaders(dashHeaders())->postJson('/api/gallery/import', ['ids' => [$item->id]])->assertOk();

    $req->refresh();
    expect($req->status)->toBe(GalleryImportRequest::REQUESTED);
    expect($req->transfer_id)->toBeNull();
    expect(GalleryImportRequest::count())->toBe(1); // pas de doublon
});
