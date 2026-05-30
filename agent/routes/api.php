<?php

use App\Http\Controllers\AgentInfoController;
use App\Http\Controllers\Pairing\PairingController;
use App\Http\Controllers\PingController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

// `/api/health` (Laravel) est minimal par design : il n'expose pas `host` ni
// `user` parce que le LAN sweep côté Flutter cible directement `/health` du
// bridge Python (port 8765), cf. ADR-002. Cette route sert juste de smoke-test
// liveness pour le pré-pairing ou un load balancer.
Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'service' => 'linkup-agent',
        'version' => config('app.version', '0.1.0'),
        'time' => now()->toIso8601String(),
    ]);
});

Route::get('/agent/info', [AgentInfoController::class, 'show']);
Route::get('/mdns/services', [AgentInfoController::class, 'services']);

Route::post('/ping', [PingController::class, 'send']);

// S2.J2 — endpoints de pairing (QR + OTP). Le tel scanne /qr.png, le
// dashboard consomme /qr en JSON pour son affichage.
Route::get('/pairing/qr.png', [PairingController::class, 'qrPng']);
Route::get('/pairing/qr', [PairingController::class, 'qrPayload']);

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
