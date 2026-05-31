<?php

use Illuminate\Support\Facades\Route;

// L'agent Linkup est purement API (le dashboard Next.js et le tel consomment
// /api/*). La racine renvoie un identifiant de service, pas la vue welcome
// par défaut de Laravel.
Route::get('/', function () {
    return response()->json([
        'service' => 'linkup-agent',
        'version' => config('app.version'),
        'docs' => 'API sur /api/* — dashboard sur http://localhost:3000',
    ]);
});
