<?php

namespace App\Http\Middleware;

use App\Services\Security\SecurityAuditService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Protège les routes de gestion des devices (liste / approbation / révocation)
 * réservées au dashboard local.
 *
 * Exige le header custom `X-Linkup-Client: dashboard`. Couplé au CORS restreint
 * (config/cors.php → seule l'origine du dashboard est autorisée), c'est une
 * protection anti-CSRF efficace : un site malveillant ouvert dans le navigateur
 * de l'utilisateur ne peut PAS envoyer ce header custom sans déclencher un
 * preflight CORS, lequel est refusé pour toute origine autre que le dashboard.
 * Sans ça, n'importe quelle page web pouvait approuver un device en pending.
 *
 * Les routes du téléphone (handshake, poll, qr) ne passent PAS par ici.
 */
class RequireDashboardClient
{
    public const HEADER = 'X-Linkup-Client';
    public const EXPECTED = 'dashboard';

    public function __construct(
        private readonly SecurityAuditService $audit,
    ) {
    }

    public function handle(Request $request, Closure $next): Response
    {
        if ($request->header(self::HEADER) !== self::EXPECTED) {
            $this->audit->log(
                SecurityAuditService::DASHBOARD_FORBIDDEN,
                payload: ['path' => $request->path(), 'method' => $request->method()],
                ip: $request->ip(),
            );

            return response()->json([
                'message' => 'Origine non autorisée : réservé au dashboard Linkup local.',
            ], 403);
        }

        return $next($request);
    }
}
