<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * S14 — Dev Preview (localhost mobile), piloté depuis le dashboard PC.
 *
 * Le dashboard liste les serveurs de dev qui tournent sur le PC, puis « expose »
 * celui à tester sur le tél. Laravel n'est qu'un relais authentifié (dashboard.client
 * + local.only) vers le bridge Python, qui fait le proxy/HTTPS réel. Aucune logique
 * métier ici : on remonte tel quel la réponse du bridge (ports, listen_port, hosts).
 */
class PreviewController extends Controller
{
    public function __construct(
        private readonly BridgeClient $bridge,
    ) {
    }

    /** GET /api/preview/ports — serveurs de dev détectés sur le PC. */
    public function ports(): JsonResponse
    {
        return $this->relay(fn () => $this->bridge->previewPorts());
    }

    /** GET /api/preview/exposed — projets actuellement exposés (+ hosts/scheme). */
    public function exposed(): JsonResponse
    {
        return $this->relay(fn () => $this->bridge->exposedPreviews());
    }

    /**
     * GET /api/preview/ca.crt — certificat PUBLIC de la CA Linkup, relayé depuis
     * le bridge. PUBLIC à dessein (hors auth.device) : le tél l'ouvre dans son
     * navigateur pour l'installer, et le navigateur n'émet aucun header d'auth.
     * Un certificat de CA est public par nature (la clé privée reste sur le PC).
     */
    public function caCertificate(): Response
    {
        try {
            $pem = $this->bridge->previewCaCertificate();
        } catch (BridgeUnavailableException $e) {
            abort(503, $e->getMessage());
        }

        return response($pem, 200, [
            'Content-Type' => 'application/x-x509-ca-cert',
            'Content-Disposition' => 'attachment; filename="linkup-ca.crt"',
        ]);
    }

    /** POST /api/preview/expose — ouvre le proxy HTTPS vers un port local. */
    public function expose(Request $request): JsonResponse
    {
        $port = $this->validatePort($request);

        return $this->relay(fn () => $this->bridge->exposePreview($port));
    }

    /** POST /api/preview/unexpose — ferme le proxy d'un projet. */
    public function unexpose(Request $request): JsonResponse
    {
        $port = $this->validatePort($request);

        return $this->relay(fn () => $this->bridge->unexposePreview($port));
    }

    private function validatePort(Request $request): int
    {
        return (int) $request->validate([
            'port' => ['required', 'integer', 'min:1', 'max:65535'],
        ])['port'];
    }

    /**
     * Exécute l'appel bridge et convertit une panne en 503 lisible (au lieu
     * d'une 500), en remontant le message du bridge (ex. « rien n'écoute sur
     * le port »).
     *
     * @param callable():array $call
     */
    private function relay(callable $call): JsonResponse
    {
        try {
            return response()->json($call());
        } catch (BridgeUnavailableException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }
    }
}
