<?php

use App\Services\Clipboard\ClipboardService;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

it('lists clipboard history for the dashboard (recent first)', function () {
    $service = app(ClipboardService::class);
    $service->receive(null, 'copié sur le PC', ClipboardService::ORIGIN_PC);
    $service->receive(null, 'copié sur le tél', ClipboardService::ORIGIN_PHONE);

    $this->withHeaders(['X-Linkup-Client' => 'dashboard', 'Accept' => 'application/json'])
        ->getJson('/api/clipboard/history')
        ->assertOk()
        ->assertJsonCount(2, 'items')
        ->assertJsonPath('items.0.content', 'copié sur le tél') // récent d'abord
        ->assertJsonPath('items.0.origin', 'phone');
});

it('refuses dashboard clipboard history without the dashboard header (403)', function () {
    $this->getJson('/api/clipboard/history')->assertStatus(403);
});
