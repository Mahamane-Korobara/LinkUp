<?php

namespace App\Services\Pairing;

use RuntimeException;

/**
 * Levée quand on tente d'approuver un device qui ne peut pas l'être
 * (ex. déjà révoqué). Mappée en 409 par le contrôleur.
 */
class DeviceNotApprovable extends RuntimeException
{
}
