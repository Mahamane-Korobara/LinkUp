<?php

namespace App\Services\Pairing;

use RuntimeException;

/**
 * Levee quand un handshake de pairing est refuse.
 *
 * `reasonCode` est un identifiant stable destine au client (ex. `otp_invalid`)
 * pour qu'il puisse afficher un message localise. `getMessage()` est la
 * description humaine pour les logs.
 */
class HandshakeRejected extends RuntimeException
{
    public function __construct(
        public readonly string $reasonCode,
        string $message,
    ) {
        parent::__construct($message);
    }
}
