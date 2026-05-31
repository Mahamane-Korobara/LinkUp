<?php

namespace App\Http\Controllers\Transfer;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AuthenticateDevice;
use App\Models\Device;
use App\Models\Transfer;
use App\Services\Transfer\TransferService;
use App\Services\Transfer\TransferTokenSigner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * S4.J2 — endpoints d'orchestration des transferts, authentifiés par le token
 * device (middleware `auth.device`).
 */
class TransferController extends Controller
{
    public function __construct(
        private readonly TransferService $transfers,
        private readonly TransferTokenSigner $tokenSigner,
    ) {
    }

    /**
     * POST /api/transfers — le tel déclare un transfert (et reçoit son id).
     */
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'filename' => 'required|string|max:255',
            'size' => 'required|integer|min:0',
            'sha256' => 'sometimes|nullable|string|size:64',
            'direction' => 'required|in:to_pc,to_phone',
            'total_chunks' => 'sometimes|nullable|integer|min:1',
        ]);

        $transfer = $this->transfers->initiate(
            device: $this->device($request),
            direction: $validated['direction'],
            filename: $validated['filename'],
            size: $validated['size'],
            sha256: $validated['sha256'] ?? null,
            totalChunks: $validated['total_chunks'] ?? null,
        );

        // Le tél pousse les chunks DIRECTEMENT au bridge avec ce token scopé.
        return response()->json($this->present($transfer) + [
            'upload_token' => $this->tokenSigner->sign($transfer->id),
            'bridge_port' => $this->bridgePort(),
        ], 201);
    }

    /**
     * GET /api/transfers/{transfer} — statut + chunks reçus (reprise).
     */
    public function show(Request $request, Transfer $transfer): JsonResponse
    {
        // Anti-IDOR : un device ne voit QUE ses propres transferts.
        abort_unless($transfer->device_id === $this->device($request)->id, 404);

        return response()->json(
            $this->present($transfer) + [
                'received_chunks' => $this->transfers->receivedChunkIndices($transfer),
            ],
        );
    }

    private function device(Request $request): Device
    {
        return $request->attributes->get(AuthenticateDevice::ATTRIBUTE);
    }

    /** Port HTTP du bridge sur ce PC (déduit de sa base_url, défaut 8765). */
    private function bridgePort(): int
    {
        $url = (string) config('services.linkup_bridge.base_url');

        return (int) (parse_url($url, PHP_URL_PORT) ?: 8765);
    }

    private function present(Transfer $transfer): array
    {
        return [
            'transfer_id' => $transfer->id,
            'filename' => $transfer->filename,
            'size' => $transfer->size,
            'direction' => $transfer->direction,
            'status' => $transfer->status,
            'total_chunks' => $transfer->total_chunks,
            'sha256' => $transfer->sha256,
        ];
    }
}
