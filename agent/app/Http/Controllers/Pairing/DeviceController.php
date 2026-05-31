<?php

namespace App\Http\Controllers\Pairing;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\Crypto\KeyManager;
use App\Services\Pairing\DeviceApprovalService;
use App\Services\Pairing\DeviceNotApprovable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * S2.J4 — gestion des devices côté PC.
 *
 * - index / approve / reject : pilotés par le dashboard `/devices`.
 * - poll : appelé par le tel après son handshake pour savoir s'il a été
 *   approuvé, et récupérer son token persistant (une seule fois).
 */
class DeviceController extends Controller
{
    public function __construct(
        private readonly DeviceApprovalService $approval,
        private readonly KeyManager $keyManager,
    ) {
    }

    /**
     * GET /api/pairing/devices — liste pour le dashboard.
     * Les pending d'abord (le plus récent en haut), puis le reste.
     */
    public function index(): JsonResponse
    {
        $devices = Device::query()
            ->orderByRaw('approved asc, revoked_at is not null asc')
            ->orderByDesc('paired_at')
            ->get()
            ->map(fn (Device $d) => $this->present($d));

        return response()->json(['devices' => $devices]);
    }

    /**
     * POST /api/pairing/devices/{device}/approve
     */
    public function approve(Device $device): JsonResponse
    {
        try {
            $this->approval->approve($device);
        } catch (DeviceNotApprovable $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        }

        return response()->json($this->present($device));
    }

    /**
     * POST /api/pairing/devices/{device}/reject
     */
    public function reject(Device $device): JsonResponse
    {
        $this->approval->reject($device);

        return response()->json($this->present($device));
    }

    /**
     * POST /api/pairing/poll — le tel demande son statut.
     *
     * Body : { device_id, signature } où signature = sign(device_id) avec la
     * clé privée du tel. On la vérifie contre la clé publique enregistrée pour
     * éviter qu'un tiers ne sonde / vole le token d'un autre device.
     *
     * Réponses :
     * - pending  → { status: 'pending' }
     * - rejected → { status: 'rejected' }
     * - approved → { status: 'approved', token: <clair|null> }
     *   (token non-null uniquement au premier appel après approbation)
     */
    public function poll(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'device_id' => 'required|string',
            'signature' => 'required|string|max:128',
        ]);

        $device = Device::find($validated['device_id']);
        if ($device === null) {
            return response()->json(['status' => 'unknown'], 404);
        }

        $signatureValid = $this->keyManager->verify(
            message: $device->id,
            signatureB64: $validated['signature'],
            publicKeyB64: $device->public_key,
        );
        if (!$signatureValid) {
            return response()->json(['message' => 'Signature invalide.'], 403);
        }

        $status = $device->status();
        if ($status !== 'approved') {
            return response()->json(['status' => $status]);
        }

        return response()->json([
            'status' => 'approved',
            'token' => $this->approval->issueTokenOnce($device),
        ]);
    }

    /**
     * Représentation JSON d'un device pour le dashboard / le tel.
     */
    private function present(Device $device): array
    {
        return [
            'device_id' => $device->id,
            'name' => $device->name,
            'fingerprint' => $device->fingerprint_sha256,
            'status' => $device->status(),
            'paired_at' => $device->paired_at?->toIso8601String(),
            'approved_at' => $device->approved_at?->toIso8601String(),
        ];
    }
}
