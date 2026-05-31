<?php

namespace App\Http\Middleware;

use App\Models\Device;
use App\Services\Security\SecurityAuditService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Symfony\Component\HttpFoundation\Response;

/**
 * Authentifie un téléphone appairé via son token persistant (S4.J2).
 *
 * Le tel envoie :
 *   - `X-Device-Id: <uuid>`            (lookup rapide, 1 seul hash à vérifier)
 *   - `Authorization: Bearer <token>`  (token clair reçu une fois après approbation)
 *
 * On vérifie le token contre le hash argon2id stocké, et que le device est
 * toujours actif (approuvé + non révoqué). Le device authentifié est exposé
 * via `$request->attributes->get('device')`.
 *
 * Attribut clé sous lequel le device authentifié est rangé sur la requête.
 */
class AuthenticateDevice
{
    public const ATTRIBUTE = 'device';

    public function __construct(
        private readonly SecurityAuditService $audit,
    ) {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $deviceId = (string) $request->header('X-Device-Id', '');
        $token = (string) $request->bearerToken();

        $device = $deviceId !== '' ? Device::find($deviceId) : null;

        if ($device === null || !$device->isActive() || $token === '' || !$this->tokenMatches($device, $token)) {
            $this->audit->log(
                SecurityAuditService::DEVICE_AUTH_FAILED,
                deviceId: $deviceId !== '' ? $deviceId : null,
                ip: $request->ip(),
            );

            return response()->json(['message' => 'Authentification device invalide.'], 401);
        }

        $request->attributes->set(self::ATTRIBUTE, $device);

        return $next($request);
    }

    /**
     * Vérifie le token clair contre le hash argon2id du device, et horodate
     * l'usage. Un seul hash à vérifier (lookup par device_id) → coût maîtrisé.
     */
    private function tokenMatches(Device $device, string $token): bool
    {
        $row = $device->tokens()->latest()->first();
        if ($row === null || !Hash::driver('argon2id')->check($token, $row->token_hash)) {
            return false;
        }
        $row->forceFill(['last_used_at' => now()])->save();

        return true;
    }
}
