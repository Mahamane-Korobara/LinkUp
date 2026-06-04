<?php

namespace App\Http\Middleware;

use App\Services\Security\SecurityAuditService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Restreint une route aux clients de la machine locale (loopback).
 *
 * Le dashboard tourne sur le MÊME PC que l'agent (localhost:3000 en dev, même
 * origine FrankenPHP en bundle) : ses requêtes — y compris les balises
 * <img>/<video> de la galerie — partent de 127.0.0.1/::1. Le téléphone et tout
 * autre hôte du LAN ont une IP non-loopback : ils sont refusés.
 *
 * Pourquoi en plus de `RequireDashboardClient` :
 * `RequireDashboardClient` (header `X-Linkup-Client` + CORS) ne bloque que les
 * NAVIGATEURS (CSRF). Un client LAN non-navigateur (curl) forge trivialement le
 * header statique. Le filtre loopback ferme ce trou : un attaquant du LAN ne
 * peut PAS lister les devices/fichiers ni pousser un fichier au tél.
 *
 * Robustesse : TrustProxies n'est pas configuré, donc Laravel ignore
 * `X-Forwarded-For` → `$request->ip()` = REMOTE_ADDR réel. FrankenPHP exécute
 * PHP en process (pas de hop proxy), l'IP du pair est donc bien celle du client
 * et n'est pas spoofable sans déjà être sur la loopback (= sur la machine).
 */
class LocalhostOnly
{
    /** IPs loopback explicites (IPv4 nominale + IPv6 sous ses deux formes). */
    private const LOOPBACK = ['127.0.0.1', '::1', '0:0:0:0:0:0:0:1'];

    public function __construct(
        private readonly SecurityAuditService $audit,
    ) {
    }

    public function handle(Request $request, Closure $next): Response
    {
        $ip = (string) $request->ip();

        if (! $this->isLoopback($ip)) {
            $this->audit->log(
                SecurityAuditService::NON_LOCAL_FORBIDDEN,
                payload: ['path' => $request->path(), 'method' => $request->method()],
                ip: $ip,
            );

            return response()->json([
                'message' => 'Réservé au PC local (origine non-loopback).',
            ], 403);
        }

        return $next($request);
    }

    private function isLoopback(string $ip): bool
    {
        // Tout 127.0.0.0/8 (certaines distros résolvent le hostname en 127.0.1.1).
        return in_array($ip, self::LOOPBACK, true) || str_starts_with($ip, '127.');
    }
}
