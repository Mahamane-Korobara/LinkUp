<?php

use App\Http\Controllers\AgentInfoController;
use App\Http\Controllers\Clipboard\ClipboardController;
use App\Http\Controllers\Dashboard\ClipboardController as DashboardClipboardController;
use App\Http\Controllers\Dashboard\FilesController;
use App\Http\Controllers\Dashboard\OutboxController;
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
// throttle:pairing (60/min/IP) : borne les tentatives de handshake.
Route::post('/pairing/handshake', [PairingController::class, 'handshake'])
    ->middleware('throttle:pairing');

// S2.J4 — gestion des devices.
// index/approve/reject = dashboard local UNIQUEMENT → protégés par
// `dashboard.client` (header custom + CORS restreint, anti-CSRF). Sans ça,
// n'importe quelle page web pouvait lister/approuver des devices.
// dashboard.client = header anti-CSRF (navigateur) ; local.only = loopback
// uniquement (bloque un hôte du LAN qui forgerait le header). Les deux ensemble
// couvrent le navigateur ET le client non-navigateur (curl).
Route::middleware(['dashboard.client', 'local.only'])->group(function () {
    Route::get('/pairing/devices', [DeviceController::class, 'index']);
    Route::post('/pairing/devices/{device}/approve', [DeviceController::class, 'approve']);
    Route::post('/pairing/devices/{device}/reject', [DeviceController::class, 'reject']);
    Route::post('/pairing/devices/{device}/rename', [DeviceController::class, 'rename']);

    // S4 — fichiers reçus, vus depuis le dashboard (ouverture sur le PC).
    Route::get('/files', [FilesController::class, 'index']);
    Route::post('/files/{transfer}/open', [FilesController::class, 'open']);

    // S5 — historique presse-papier vu depuis le dashboard.
    Route::get('/clipboard/history', [DashboardClipboardController::class, 'index']);

    // S6 — envoi PC → tél : le dashboard dépose un fichier pour un tél.
    Route::post('/outbox/{device}', [OutboxController::class, 'send']);
});

// Aperçu d'un fichier reçu, servi INLINE pour les balises <img>/<video> du
// dashboard (Galerie). Hors `dashboard.client` car ces balises ne peuvent pas
// émettre le header custom ; lecture seule, fichiers terminés uniquement.
// MAIS local.only : les <img>/<video> du dashboard partent de la loopback, donc
// un hôte du LAN ne peut pas aspirer les fichiers reçus via leur UUID.
Route::get('/files/{transfer}/raw', [FilesController::class, 'raw'])
    ->middleware('local.only');

// poll = appelé par le TEL (authentifié par signature Ed25519), pas le
// dashboard → reste ouvert (le tel ne peut pas envoyer le header dashboard).
// throttle:pairing (60/min/IP) : couvre la cadence légitime du tél (2 s = 30/min)
// et borne le flooding de signatures invalides (anti-amplification audit).
Route::post('/pairing/poll', [DeviceController::class, 'poll'])
    ->middleware('throttle:pairing');

// Endpoints authentifiés par le token persistant du tel (middleware
// auth.device : X-Device-Id + Bearer <token>).
Route::middleware('auth.device')->group(function () {
    // Vérif d'appairage : le tel l'appelle pour savoir si le PC le connaît
    // ENCORE (après un migrate:fresh / une révocation, son token est invalide
    // → 401 → le tel sait qu'il doit ré-appairer).
    Route::get('/me', function (Request $request) {
        $device = $request->attributes->get(\App\Http\Middleware\AuthenticateDevice::ATTRIBUTE);

        return response()->json([
            'device_id' => $device->id,
            'name' => $device->name,
            'approved' => $device->approved,
            'fingerprint' => $device->fingerprint_sha256,
        ]);
    });

    // S4.J2 — transferts de fichiers.
    Route::get('/transfers', [TransferController::class, 'index']);
    // S6 — fichiers entrants (PC → tél), AVANT /{transfer} pour ne pas matcher
    // « incoming » comme un id.
    Route::get('/transfers/incoming', [TransferController::class, 'incoming']);
    Route::post('/transfers', [TransferController::class, 'store']);
    Route::get('/transfers/{transfer}', [TransferController::class, 'show']);
    Route::get('/transfers/{transfer}/download', [TransferController::class, 'download']);
    Route::post('/transfers/{transfer}/complete', [TransferController::class, 'complete']);
    Route::post('/transfers/{transfer}/open', [TransferController::class, 'open']);
    // S6 — le tél confirme avoir enregistré un fichier reçu du PC.
    Route::post('/transfers/{transfer}/delivered', [TransferController::class, 'delivered']);

    // S5 — presse-papier + lien rapide.
    Route::get('/clipboard', [ClipboardController::class, 'index']);
    Route::post('/clipboard', [ClipboardController::class, 'push']);
    Route::get('/clipboard/pc', [ClipboardController::class, 'pc']);
    Route::post('/link/open', [ClipboardController::class, 'openLink']);

    // S6 — l'envoi des photos passe par le module transfert (/transfers) : le tél
    // choisit les médias et les pousse comme des fichiers normaux (pas d'index).
});

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
