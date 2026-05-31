<?php

namespace App\Support;

/**
 * Génération de tokens aléatoires URL-safe, centralisée pour éviter la
 * duplication entre PairingService (OTP du QR) et DeviceApprovalService
 * (token persistant du device).
 */
final class RandomToken
{
    /**
     * `$bytes` octets aléatoires encodés en base64url (sans `+`, `/`, `=`),
     * sûrs à passer dans une URL/QR sans échappement.
     *
     * 32 octets → 43 caractères.
     */
    public static function urlSafe(int $bytes = 32): string
    {
        return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
    }
}
