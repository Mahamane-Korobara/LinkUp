<?php

namespace App\Http\Controllers\Pairing;

use App\Http\Controllers\Controller;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Pairing\PairingService;
use Endroid\QrCode\Builder\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;

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
        private readonly BridgeClient $bridge,
    ) {
    }

    /**
     * Génère le PNG du QR avec un OTP frais.
     * Pas de cache : chaque appel = nouvel OTP (sinon anti-rejeu inutile).
     */
    public function qrPng(): Response
    {
        $url = $this->buildFreshPairingUrl();

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
        $otp = $this->pairing->createOtp();
        $ip = $this->resolveLocalIp();
        $port = (int) config('services.linkup.pairing_port', 8000);
        $url = $this->pairing->buildPairingUrl($ip, $port, $otp->token);

        return response()->json([
            'url' => $url,
            'otp' => $otp->token,
            'expires_at' => $otp->expiresAt->format('c'),
            'ttl_seconds' => PairingService::OTP_TTL_SECONDS,
        ]);
    }

    private function buildFreshPairingUrl(): string
    {
        $otp = $this->pairing->createOtp();
        $ip = $this->resolveLocalIp();
        $port = (int) config('services.linkup.pairing_port', 8000);
        return $this->pairing->buildPairingUrl($ip, $port, $otp->token);
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
