<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\Transfer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * S6 — envoi PC → tél (auth dashboard.client).
 *
 * Le dashboard dépose un fichier choisi sur le PC dans l'outbox et crée un
 * transfert `to_phone` prêt à être récupéré ; le tél le télécharge en polling
 * (cf. TransferController::incoming / download). Les octets transitent par
 * Laravel (pas le bridge) : la source est le navigateur local, sur le LAN.
 */
class OutboxController extends Controller
{
    /** Plafond par fichier (LAN, alpha) : 200 Mo. */
    private const MAX_BYTES = 200 * 1024 * 1024;

    /**
     * POST /api/outbox/{device} — dépose un fichier pour ce tél.
     */
    public function send(Request $request, Device $device): JsonResponse
    {
        abort_unless($device->approved, 403, 'Téléphone non appairé.');

        $request->validate([
            'file' => ['required', 'file', 'max:' . (self::MAX_BYTES / 1024)],
        ]);

        $file = $request->file('file');
        $original = $file->getClientOriginalName() ?: 'fichier';

        // Nom stocké unique (anti-collision + anti-traversal : on ne garde que le
        // basename d'origine, préfixé d'un uuid).
        $storedName = Str::uuid()->toString() . '__' . basename($original);

        $dir = $this->outboxDir();
        if (! is_dir($dir)) {
            mkdir($dir, 0700, true);
        }
        $file->move($dir, $storedName);

        $transfer = Transfer::create([
            'device_id' => $device->id,
            'filename' => $original,
            'stored_name' => $storedName,
            'size' => filesize($dir . DIRECTORY_SEPARATOR . $storedName) ?: 0,
            'direction' => Transfer::TO_PHONE,
            'status' => Transfer::COMPLETED,
            'completed_at' => now(),
        ]);

        return response()->json([
            'transfer_id' => $transfer->id,
            'filename' => $transfer->filename,
            'size' => $transfer->size,
            'device' => $device->name,
        ], 201);
    }

    private function outboxDir(): string
    {
        return rtrim((string) config('services.linkup.outbox'), DIRECTORY_SEPARATOR);
    }
}
