<?php

namespace App\Services\Pairing;

use App\Services\Crypto\KeyManager;
use DateTimeImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Logique métier du pairing PC↔tel (S2).
 *
 * - Génère des OTPs uniques courts (60s) à insérer dans le QR
 * - Consomme un OTP exactement une fois (anti-rejeu)
 * - Construit l'URL `linkup://...` complète qui ira dans le QR
 *
 * La vraie crypto handshake Noise IK arrive en S2.J3.
 */
class PairingService
{
    /** Durée de vie d'un OTP avant qu'il soit invalide. */
    public const OTP_TTL_SECONDS = 60;

    /** Délai au-delà duquel les OTPs sont supprimés du disque (vs juste invalides). */
    public const PURGE_AFTER_SECONDS = 300; // 5 minutes

    public function __construct(
        private readonly KeyManager $keyManager,
    ) {
    }

    /**
     * Crée et persiste un nouvel OTP. Renvoie le DTO incluant le token plain.
     * Le token n'est PAS hashé en base car il a une TTL très courte (60s).
     */
    public function createOtp(): PairingOtp
    {
        $token = $this->generateToken();
        $now = new DateTimeImmutable();
        $expiresAt = $now->modify('+' . self::OTP_TTL_SECONDS . ' seconds');

        $id = DB::table('pairing_otps')->insertGetId([
            'token' => $token,
            'expires_at' => $expiresAt->format('Y-m-d H:i:s'),
            'created_at' => $now->format('Y-m-d H:i:s'),
            'updated_at' => $now->format('Y-m-d H:i:s'),
        ]);

        return new PairingOtp(
            id: (int) $id,
            token: $token,
            expiresAt: $expiresAt,
        );
    }

    /**
     * Consomme un OTP. Renvoie true si l'OTP était valide ET non encore consommé.
     * Atomique : un OTP utilisé deux fois en parallèle n'aboutit qu'une seule fois.
     */
    public function consumeOtp(string $token): bool
    {
        $now = (new DateTimeImmutable())->format('Y-m-d H:i:s');

        $affected = DB::table('pairing_otps')
            ->where('token', $token)
            ->whereNull('consumed_at')
            ->where('expires_at', '>', $now)
            ->update([
                'consumed_at' => $now,
                'updated_at' => $now,
            ]);

        return $affected > 0;
    }

    /**
     * Supprime les OTPs vieux (> PURGE_AFTER_SECONDS). À appeler depuis un
     * Scheduler en S3.J5 (T3.18). Renvoie le nombre supprimés.
     */
    public function purgeExpired(): int
    {
        $cutoff = (new DateTimeImmutable())
            ->modify('-' . self::PURGE_AFTER_SECONDS . ' seconds')
            ->format('Y-m-d H:i:s');

        return DB::table('pairing_otps')
            ->where('expires_at', '<', $cutoff)
            ->delete();
    }

    /**
     * Construit l'URL `linkup://...` qui sera encodée dans le QR.
     *
     * Format (cf. plan T2.6) : `linkup://<ip>:<port>?pk=<base64>&otp=<base64>&v=1`
     *
     * - `<port>` = port HTTP Laravel (Flutter va connecter le handshake dessus)
     * - `pk` = clé publique Ed25519 de cet agent (base64, urlencoded)
     * - `otp` = token plain (base64url, urlencoded)
     * - `v=1` = version du protocole pairing
     */
    public function buildPairingUrl(string $ip, int $port, string $otpToken): string
    {
        $publicKey = $this->keyManager->publicKey();

        return sprintf(
            'linkup://%s:%d?pk=%s&otp=%s&v=1',
            $ip,
            $port,
            rawurlencode($publicKey),
            rawurlencode($otpToken),
        );
    }

    /**
     * 32 octets aléatoires en base64url (43 caractères, sans `+`/`/`/`=`),
     * URL-safe pour passer dans le QR sans échappement compliqué.
     */
    private function generateToken(): string
    {
        $raw = random_bytes(32);
        // base64url : remplace +/=  par -_ (et trim le padding)
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }
}
