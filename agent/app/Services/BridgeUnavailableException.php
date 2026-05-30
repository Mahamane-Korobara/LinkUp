<?php

namespace App\Services;

use RuntimeException;

/**
 * Levée quand le bridge Python ne répond pas. Les controllers/routes la
 * traduisent en HTTP 503 (Service Unavailable) au lieu d'une stacktrace.
 */
class BridgeUnavailableException extends RuntimeException
{
}
