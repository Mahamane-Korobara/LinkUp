<?php

namespace App\Http\Controllers\Transfer;

use App\Http\Controllers\Controller;
use App\Http\Middleware\AuthenticateDevice;
use App\Models\Device;
use App\Models\Transfer;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Transfer\InboxLocator;
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
            // PC→tél (to_phone) pas encore implémenté → on n'accepte que to_pc.
            'direction' => 'required|in:to_pc',
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
     * GET /api/transfers/incoming — fichiers que le PC a envoyés à CE tél
     * (sens to_phone, prêts), pas encore récupérés. Le tél poll cet endpoint.
     */
    public function incoming(Request $request): JsonResponse
    {
        $transfers = Transfer::query()
            ->where('device_id', $this->device($request)->id)
            ->where('direction', Transfer::TO_PHONE)
            ->where('status', Transfer::COMPLETED)
            ->latest()
            ->limit(100)
            ->get()
            ->map(fn (Transfer $t) => $this->present($t));

        return response()->json(['transfers' => $transfers]);
    }

    /**
     * POST /api/transfers/{transfer}/delivered — le tél confirme avoir récupéré
     * et enregistré un fichier to_phone (→ disparaît de incoming).
     */
    public function delivered(Request $request, Transfer $transfer): JsonResponse
    {
        abort_unless($transfer->device_id === $this->device($request)->id, 404);
        abort_unless($transfer->direction === Transfer::TO_PHONE, 422);

        $transfer->forceFill(['status' => Transfer::DELIVERED])->save();

        return response()->json(['ok' => true]);
    }

    /**
     * GET /api/transfers — historique des transferts de CE tél (récents d'abord).
     */
    public function index(Request $request): JsonResponse
    {
        $transfers = Transfer::query()
            ->where('device_id', $this->device($request)->id)
            ->latest()
            ->limit(100)
            ->get()
            ->map(fn (Transfer $t) => $this->present($t));

        return response()->json(['transfers' => $transfers]);
    }

    /**
     * GET /api/transfers/{transfer} — statut + chunks reçus (reprise).
     */
    public function show(Request $request, Transfer $transfer): JsonResponse
    {
        // Anti-IDOR : un device ne voit QUE ses propres transferts.
        abort_unless($transfer->device_id === $this->device($request)->id, 404);

        return response()->json($this->present($transfer));
    }

    /**
     * POST /api/transfers/{transfer}/complete — le tél confirme la fin du
     * transfert (le finalize s'est fait DIRECTEMENT sur le bridge, donc Laravel
     * ne le sait pas autrement). Stocke le nom final du fichier dans l'inbox.
     */
    public function complete(Request $request, Transfer $transfer): JsonResponse
    {
        abort_unless($transfer->device_id === $this->device($request)->id, 404);

        $validated = $request->validate([
            'stored_name' => 'sometimes|nullable|string|max:255',
        ]);

        $this->transfers->complete($transfer, $validated['stored_name'] ?? null);

        return response()->json($this->present($transfer->fresh()));
    }

    /**
     * GET /api/transfers/{transfer}/download — sert le fichier reçu au tél, pour
     * qu'il l'ouvre LOCALEMENT (Laravel lit l'inbox, même PC/user que le bridge).
     */
    public function download(Request $request, Transfer $transfer): \Symfony\Component\HttpFoundation\Response
    {
        abort_unless($transfer->device_id === $this->device($request)->id, 404);

        $name = $transfer->stored_name ?: $transfer->filename;

        // to_phone : sert depuis l'outbox (fichier déposé par le PC). Sinon (to_pc)
        // : sert depuis l'inbox (re-téléchargement de ce que le tél a envoyé).
        $isToPhone = $transfer->direction === Transfer::TO_PHONE;
        $okStatuses = $isToPhone
            ? [Transfer::COMPLETED, Transfer::DELIVERED]
            : [Transfer::COMPLETED];

        if (! in_array($transfer->status, $okStatuses, true) || $name === null) {
            return response()->json(['message' => 'Transfert non disponible.'], 409);
        }

        if ($isToPhone) {
            // Outbox : stockage plat (le PC y dépose le fichier choisi).
            $base = realpath((string) config('services.linkup.outbox'));
            $path = $base !== false
                ? realpath($base . DIRECTORY_SEPARATOR . basename($name))
                : false;
            abort_unless(
                $path !== false && str_starts_with($path, $base . DIRECTORY_SEPARATOR) && is_file($path),
                404,
            );

            // Pour to_phone, on présente le nom d'origine (lisible), pas le storedName.
            return response()->download($path, $transfer->filename);
        }

        // to_pc : inbox rangée par catégorie → le stored_name est un chemin
        // relatif (« photos/IMG.jpg ») re-résolu (avec fallback) par le locator.
        $path = InboxLocator::fromConfig()->locate($name);
        abort_if($path === null, 404);

        return response()->download($path, basename($name));
    }

    /**
     * POST /api/transfers/{transfer}/open — ouvre le fichier reçu dans l'app
     * par défaut du PC (le user n'a pas à fouiller dans ~/Linkup/Inbox).
     */
    public function open(Request $request, Transfer $transfer, BridgeClient $bridge): JsonResponse
    {
        abort_unless($transfer->device_id === $this->device($request)->id, 404);

        $name = $transfer->stored_name ?: $transfer->filename;
        if ($transfer->status !== Transfer::COMPLETED || $name === null) {
            return response()->json(['message' => 'Transfert non terminé.'], 409);
        }

        try {
            $bridge->openInbox($name);
        } catch (BridgeUnavailableException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }

        return response()->json(['ok' => true]);
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
            'created_at' => $transfer->created_at?->toIso8601String(),
            'completed_at' => $transfer->completed_at?->toIso8601String(),
        ];
    }
}
