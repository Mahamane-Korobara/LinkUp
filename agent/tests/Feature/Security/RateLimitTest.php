<?php

use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

it('throttles /api/pairing/poll to bound flooding (60/min/IP)', function () {
    // Le throttle court AVANT le contrôleur : même un corps invalide (422)
    // compte. 60 passent, le 61e est rejeté en 429 → borne l'amplification du
    // journal d'audit et le DoS, tout en laissant le tél poller (30/min).
    for ($i = 0; $i < 60; $i++) {
        expect($this->postJson('/api/pairing/poll', [])->status())->not->toBe(429);
    }

    $this->postJson('/api/pairing/poll', [])->assertStatus(429);
});

it('does not throttle the public health endpoint below the api ceiling', function () {
    // Smoke : le ping de statut du dashboard (toutes les 5 s) ne doit pas sauter.
    for ($i = 0; $i < 30; $i++) {
        $this->getJson('/api/health')->assertOk();
    }
});
