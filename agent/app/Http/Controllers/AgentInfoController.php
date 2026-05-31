<?php

namespace App\Http\Controllers;

use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Crypto\KeyManager;
use Illuminate\Http\JsonResponse;

class AgentInfoController extends Controller
{
    public function __construct(
        private readonly BridgeClient $bridge,
        private readonly KeyManager $keys,
    ) {
    }

    /**
     * GET /api/agent/info — infos mDNS de l'agent local (proxifié via le bridge).
     */
    public function show(): JsonResponse
    {
        try {
            $info = $this->bridge->localInfo();
        } catch (BridgeUnavailableException $e) {
            return response()->json(['error' => $e->getMessage()], 503);
        }

        return response()->json([
            'name' => $info['instance_name'] ?? config('app.name'),
            // Vraie empreinte SHA-256 de la clé publique Ed25519 locale (S2.J1),
            // pas le 'pending' du bridge mDNS qui ne connaît pas la paire de clés.
            'fingerprint' => $this->keys->fingerprint(),
            'agent_id' => $info['agent_id'] ?? null,
            'version' => $info['version'] ?? config('app.version', '0.1.0'),
            'reverb_port' => $info['port'] ?? null,
            'bridge_port' => $info['bridge_port'] ?? null,
            'source' => 'bridge',
        ]);
    }

    /**
     * GET /api/mdns/services — liste des autres agents Linkup vus sur le LAN.
     */
    public function services(): JsonResponse
    {
        try {
            return response()->json($this->bridge->discoveredServices());
        } catch (BridgeUnavailableException $e) {
            return response()->json(['error' => $e->getMessage()], 503);
        }
    }
}
