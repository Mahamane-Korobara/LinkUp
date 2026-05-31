<?php

use App\Http\Controllers\AgentInfoController;
use App\Http\Controllers\Pairing\DeviceController;
use App\Http\Controllers\Pairing\PairingController;
use App\Http\Controllers\PingController;
use App\Http\Controllers\Transfer\TransferController;
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

// Smoke-test Reverb e2e délibérément conservé (S1.J1) : prouve que le wiring
// temps réel fonctionne tant que les events métier ne sont pas branchés côté
// dashboard. À retirer quand DeviceApproved/PairingPendingApproval seront
// réellement consommés.
Route::post('/ping', [PingController::class, 'send']);

// S2.J2 — endpoints de pairing (QR + OTP). Le tel scanne /qr.png, le
// dashboard consomme /qr en JSON pour son affichage.
Route::get('/pairing/qr.png', [PairingController::class, 'qrPng']);
Route::get('/pairing/qr', [PairingController::class, 'qrPayload']);

// S2.J3 — handshake reçu du tel après scan QR. Le tel envoie sa pubkey +
// l'OTP + signature(otp || tel_pubkey). Réponse : pc_pubkey + status.
Route::post('/pairing/handshake', [PairingController::class, 'handshake']);

// S2.J4 — gestion des devices.
// index/approve/reject = dashboard local UNIQUEMENT → protégés par
// `dashboard.client` (header custom + CORS restreint, anti-CSRF). Sans ça,
// n'importe quelle page web pouvait lister/approuver des devices.
Route::middleware('dashboard.client')->group(function () {
    Route::get('/pairing/devices', [DeviceController::class, 'index']);
    Route::post('/pairing/devices/{device}/approve', [DeviceController::class, 'approve']);
    Route::post('/pairing/devices/{device}/reject', [DeviceController::class, 'reject']);
    Route::post('/pairing/devices/{device}/rename', [DeviceController::class, 'rename']);
});

// poll = appelé par le TEL (authentifié par signature Ed25519), pas le
// dashboard → reste ouvert (le tel ne peut pas envoyer le header dashboard).
Route::post('/pairing/poll', [DeviceController::class, 'poll']);

// S4.J2 — transferts de fichiers, authentifiés par le token persistant du tel
// (middleware auth.device : X-Device-Id + Bearer <token>).
Route::middleware('auth.device')->group(function () {
    Route::post('/transfers', [TransferController::class, 'store']);
    Route::get('/transfers/{transfer}', [TransferController::class, 'show']);
});

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
