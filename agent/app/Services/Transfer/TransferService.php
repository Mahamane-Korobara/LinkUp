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

    /** Enregistre un chunk validé (idempotent sur (transfer, index)). */
    public function recordChunk(Transfer $transfer, int $index, string $sha256): void
    {
        $transfer->chunks()->updateOrCreate(
            ['chunk_index' => $index],
            ['sha256' => $sha256, 'received_at' => now()],
        );
        if ($transfer->status === Transfer::PENDING) {
            $transfer->forceFill(['status' => Transfer::UPLOADING])->save();
        }
    }

    /** Index des chunks déjà reçus, triés (reprise). */
    public function receivedChunkIndices(Transfer $transfer): array
    {
        return $transfer->chunks()
            ->orderBy('chunk_index')
            ->pluck('chunk_index')
            ->all();
    }

    public function complete(Transfer $transfer): Transfer
    {
        $transfer->forceFill([
            'status' => Transfer::COMPLETED,
            'completed_at' => now(),
        ])->save();

        return $transfer;
    }

    public function fail(Transfer $transfer): Transfer
    {
        $transfer->forceFill(['status' => Transfer::FAILED])->save();

        return $transfer;
    }

    public function cancel(Transfer $transfer): Transfer
    {
        if (!$transfer->isTerminal()) {
            $transfer->forceFill(['status' => Transfer::CANCELLED])->save();
        }

        return $transfer;
    }
}
