<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Transfer;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use Illuminate\Http\JsonResponse;

/**
 * S4 — fichiers reçus, vus depuis le dashboard PC (auth dashboard.client).
 *
 * Liste les transferts tél→PC terminés et permet de les ouvrir sur le PC.
 */
class FilesController extends Controller
{
    /**
     * GET /api/files — fichiers reçus (tous devices), récents d'abord.
     */
    public function index(): JsonResponse
    {
        $files = Transfer::query()
            ->where('direction', Transfer::TO_PC)
            ->where('status', Transfer::COMPLETED)
            ->with('device:id,name')
            ->latest('completed_at')
            ->limit(200)
            ->get()
            ->map(fn (Transfer $t) => [
                'transfer_id' => $t->id,
                'filename' => $t->stored_name ?: $t->filename,
                'size' => $t->size,
                'device' => $t->device?->name,
                'completed_at' => $t->completed_at?->toIso8601String(),
            ]);

        return response()->json(['files' => $files]);
    }

    /**
     * POST /api/files/{transfer}/open — ouvre le fichier dans l'app par défaut du PC.
     */
    public function open(Transfer $transfer, BridgeClient $bridge): JsonResponse
    {
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
}
