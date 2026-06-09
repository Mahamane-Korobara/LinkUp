<?php

namespace App\Http\Controllers\Pairing;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\Crypto\KeyManager;
use App\Services\Pairing\DeviceApprovalService;
use App\Services\Pairing\DeviceNotApprovable;
use App\Services\Security\SecurityAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * S2.J4 — gestion des devices côté PC.
 *
 * - index / approve / destroy : pilotés par le dashboard `/devices`.
 * - poll : appelé par le tel après son handshake pour savoir s'il a été
 *   approuvé, et récupérer son token persistant (une seule fois).
 */
class DeviceController extends Controller
{
    public function __construct(
        private readonly DeviceApprovalService $approval,
        private readonly KeyManager $keyManager,
        private readonly SecurityAuditService $audit,
    ) {
    }

    /**
     * GET /api/pairing/devices — liste pour le dashboard.
     * Les pending d'abord (le plus récent en haut), puis le reste.
     */
    public function index(): JsonResponse
    {
        // Révoque les pending expirés (> 2 min) avant d'afficher la liste.
        $this->approval->expireStalePending();

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
     * DELETE /api/pairing/devices/{device}
     *
     * Refuse un pending OU révoque un approuvé : dans les deux cas le device ne
     * sert plus à rien, on le SUPPRIME (au lieu de garder une ligne « refusé »
     * dans le dashboard). Le tél le découvre via un poll 404 (pending) ou un 401
     * (approuvé : device + token disparus).
     */
    public function destroy(Request $request, Device $device): JsonResponse
    {
        $deviceId = $device->id;
        $this->approval->remove($device);
        $this->audit->log(
            SecurityAuditService::DEVICE_REJECTED,
            deviceId: $deviceId,
            ip: $request->ip(),
        );

        return response()->json(['deleted' => true]);
    }

    /**
     * POST /api/pairing/devices/{device}/rename — renomme un device (S3.J4 T3.15).
     */
    public function rename(Request $request, Device $device): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
        ]);

        $device->forceFill(['name' => trim($validated['name'])])->save();

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
            $this->audit->log(
                SecurityAuditService::POLL_SIGNATURE_INVALID,
                deviceId: $device->id,
                ip: $request->ip(),
            );

            return response()->json(['message' => 'Signature invalide.'], 403);
        }

        // Expiration paresseuse : un pending trop vieux est supprimé ici même.
        // On répond « rejected » dans la foulée (le device est encore en mémoire) ;
        // la poll suivante tombera sur un 404, que le tel interprète aussi comme
        // un refus.
        if ($this->approval->isStalePending($device)) {
            $this->approval->remove($device);

            return response()->json(['status' => 'rejected']);
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
            'model' => $device->model,
            'platform' => $device->platform,
            'os_version' => $device->os_version,
            'fingerprint' => $device->fingerprint_sha256,
            'status' => $device->status(),
            'paired_at' => $device->paired_at?->toIso8601String(),
            'approved_at' => $device->approved_at?->toIso8601String(),
        ];
    }
}
