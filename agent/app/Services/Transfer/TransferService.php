<?php

namespace App\Services\Transfer;

use App\Events\FileTransferRequested;
use App\Models\Device;
use App\Models\Transfer;
use Illuminate\Support\Facades\Log;
use InvalidArgumentException;

/**
 * S4.J2 — orchestration métier des transferts de fichiers.
 *
 * Laravel tient l'état (table `transfers`) et notifie via Reverb ; les chunks
 * binaires eux-mêmes transitent par le bridge Python (cf. bridge/.../transfer).
 */
class TransferService
{
    private const DIRECTIONS = [Transfer::TO_PC, Transfer::TO_PHONE];

    /**
     * Crée un transfert en `pending` et broadcast FileTransferRequested.
     */
    public function initiate(
        Device $device,
        string $direction,
        string $filename,
        int $size,
        ?string $sha256 = null,
        ?int $totalChunks = null,
    ): Transfer {
        if (!in_array($direction, self::DIRECTIONS, true)) {
            throw new InvalidArgumentException("Direction invalide : {$direction}");
        }

        $transfer = Transfer::create([
            'device_id' => $device->id,
            'filename' => trim($filename),
            'size' => max(0, $size),
            'sha256' => $sha256,
            'direction' => $direction,
            'status' => Transfer::PENDING,
            'total_chunks' => $totalChunks,
        ]);

        // Best-effort : un Reverb down ne doit pas faire échouer l'initiation
        // (le statut reste interrogeable en polling).
        try {
            FileTransferRequested::dispatch($transfer);
        } catch (\Throwable $e) {
            Log::warning('Broadcast FileTransferRequested échoué : ' . $e->getMessage());
        }

        return $transfer;
    }

    public function complete(Transfer $transfer, ?string $storedName = null): Transfer
    {
        $attrs = [
            'status' => Transfer::COMPLETED,
            'completed_at' => now(),
        ];
        if ($storedName !== null && trim($storedName) !== '') {
            $attrs['stored_name'] = trim($storedName);
        }
        $transfer->forceFill($attrs)->save();

        return $transfer;
    }
}
