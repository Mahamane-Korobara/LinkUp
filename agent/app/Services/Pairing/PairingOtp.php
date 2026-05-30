<?php

namespace App\Services\Pairing;

use DateTimeImmutable;

/**
 * DTO immuable d'un OTP de pairing fraîchement créé.
 * Renvoyé par PairingService::createOtp() et sérialisé dans /api/pairing/qr.
 */
final class PairingOtp
{
    public function __construct(
        public readonly int $id,
        public readonly string $token,
        public readonly DateTimeImmutable $expiresAt,
    ) {
    }

    public function ttlSeconds(): int
    {
        $diff = $this->expiresAt->getTimestamp() - (new DateTimeImmutable())->getTimestamp();
        return max(0, $diff);
    }
}
