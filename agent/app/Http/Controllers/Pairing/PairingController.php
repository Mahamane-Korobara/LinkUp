<?php

namespace App\Http\Controllers\Pairing;

use App\Events\PairingPendingApproval;
use App\Http\Controllers\Controller;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Crypto\KeyManager;
use App\Services\Pairing\HandshakeRejected;
use App\Services\Pairing\PairingHandshakeService;
use App\Services\Pairing\PairingService;
use App\Services\Security\SecurityAuditService;
use Endroid\QrCode\Builder\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;

/**
 * Endpoints S2.J2 — génération QR de pairing.
 *
 * - GET /api/pairing/qr.png  → image PNG du QR avec un OTP frais (60s)
 * - GET /api/pairing/qr      → JSON {url, otp, expires_at, ttl_seconds}
 *
 * Le dashboard Next.js consomme le JSON pour afficher le QR + timer (T2.8).
 * Le tel scanne directement le PNG.
 */
class PairingController extends Controller
{
    public function __construct(
        private readonly PairingService $pairing,
        private readonly PairingHandshakeService $handshake,
        private readonly BridgeClient $bridge,
        private readonly KeyManager $keyManager,
        private readonly SecurityAuditService $audit,
    ) {
    }

    /**
     * Génère le PNG du QR avec un OTP frais.
     * Pas de cache : chaque appel = nouvel OTP (sinon anti-rejeu inutile).
     */
    public function qrPng(): Response
    {
        [, $url] = $this->freshPairing();

        // endroid/qr-code v6 : Builder est immutable, params via constructeur.
        $qr = (new Builder(
            data: $url,
            size: 400,
            margin: 16,
        ))->build();

        return response($qr->getString(), 200, [
            'Content-Type' => $qr->getMimeType(),
            'Cache-Control' => 'no-store, no-cache, must-revalidate',
        ]);
    }

    /**
     * Variante JSON : pratique pour le dashboard qui veut afficher l'URL +
     * un timer countdown à côté du QR (et regénérer à expiration).
     */
    public function qrPayload(): JsonResponse
    {
        [$otp, $url] = $this->freshPairing();

        return response()->json([
            'url' => $url,
            'otp' => $otp->token,
            'expires_at' => $otp->expiresAt->format('c'),
            'ttl_seconds' => PairingService::OTP_TTL_SECONDS,
        ]);
    }

    /**
     * S2.J3 — POST /api/pairing/handshake
     *
     * Le tel envoie sa clé publique + l'OTP scanné + la signature de
     * (otp || tel_pubkey). On valide, créé un Device pending, et broadcast
     * un event Reverb pour le popup d'approbation du dashboard.
     */
    public function handshake(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'tel_public_key' => 'required|string|max:88',
            'otp' => 'required|string|max:64',
            'signature' => 'required|string|max:128',
            'device_name' => 'sometimes|nullable|string|max:255',
            'device_model' => 'sometimes|nullable|string|max:255',
            'device_platform' => 'sometimes|nullable|string|max:255',
            'device_os' => 'sometimes|nullable|string|max:255',
        ]);

        try {
            $device = $this->handshake->handshake(
                telPublicKeyBase64: $validated['tel_public_key'],
                otp: $validated['otp'],
                signatureBase64: $validated['signature'],
                deviceName: $validated['device_name'] ?? null,
                metadata: [
                    'model' => $validated['device_model'] ?? null,
                    'platform' => $validated['device_platform'] ?? null,
                    'os_version' => $validated['device_os'] ?? null,
                ],
            );
        } catch (HandshakeRejected $e) {
            $this->audit->log(
                SecurityAuditService::HANDSHAKE_REJECTED,
                payload: ['reason_code' => $e->reasonCode],
                ip: $request->ip(),
            );

            return response()->json([
                'status' => 'rejected',
                'reason_code' => $e->reasonCode,
                'message' => $e->getMessage(),
            ], 422);
        }

        // Notification temps-réel best-effort : le dashboard fonctionne aussi
        // en polling, donc un Reverb indisponible ne doit PAS faire échouer le
        // pairing. On log et on continue.
        try {
            PairingPendingApproval::dispatch($device);
        } catch (\Throwable $e) {
            Log::warning('Broadcast PairingPendingApproval échoué (pairing OK quand même): ' . $e->getMessage());
        }

        return response()->json([
            'status' => $device->approved ? 'approved' : 'pending_approval',
            'device_id' => $device->id,
            // Empreinte DU TÉL : c'est elle que le dashboard affiche, le tel
            // montre la même pour que l'utilisateur compare les deux écrans.
            'device_fingerprint' => $device->fingerprint_sha256,
            'pc_public_key' => $this->keyManager->publicKey(),
            'pc_fingerprint' => $this->keyManager->fingerprint(),
            'pc_name' => gethostname() ?: 'PC Linkup',
        ]);
    }

    /**
     * Crée un OTP frais et l'URL `linkup://` correspondante (IP LAN + port
     * Laravel). Source unique pour le PNG du QR et son équivalent JSON.
     *
     * @return array{0: \App\Services\Pairing\PairingOtp, 1: string} [otp, url]
     */
    private function freshPairing(): array
    {
        $otp = $this->pairing->createOtp();
        $url = $this->pairing->buildPairingUrl(
            $this->resolveLocalIp(),
            (int) config('services.linkup.pairing_port', 8000),
            $otp->token,
        );

        return [$otp, $url];
    }

    /**
     * Récupère l'IP LAN de cette machine via le bridge mDNS.
     * Si le bridge est down, on retombe sur 127.0.0.1 (le QR sera utilisable
     * en démo locale uniquement).
     */
    private function resolveLocalIp(): string
    {
        try {
            $info = $this->bridge->localInfo();
            return $info['ip'] ?? '127.0.0.1';
        } catch (BridgeUnavailableException) {
            return '127.0.0.1';
        }
    }
}
