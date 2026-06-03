<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\Transfer;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Transfer\InboxLocator;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\Response;

/**
 * S4 — fichiers reçus, vus depuis le dashboard PC (auth dashboard.client).
 *
 * Liste les transferts tél→PC terminés, expose leur catégorie (photos / video /
 * fichiers) pour les onglets Galerie/Fichier du dashboard, sert l'aperçu (raw)
 * et permet de les ouvrir sur le PC.
 */
class FilesController extends Controller
{
    /** Extensions classées « image » (miroir du bridge, pour anciens fichiers plats). */
    private const IMAGE_EXTS = [
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
        'tif', 'tiff', 'svg', 'avif', 'ico',
    ];

    /** Extensions classées « vidéo ». */
    private const VIDEO_EXTS = [
        'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', '3g2',
        'flv', 'wmv', 'mpeg', 'mpg', 'ts', 'm2ts', 'hevc',
    ];

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
                'filename' => basename($t->stored_name ?: $t->filename ?: ''),
                'category' => $this->category($t->stored_name, $t->filename),
                'size' => $t->size,
                'device' => $t->device?->name,
                'completed_at' => $t->completed_at?->toIso8601String(),
            ]);

        return response()->json(['files' => $files]);
    }

    /**
     * GET /api/files/{transfer}/raw — sert les octets du fichier reçu (aperçu).
     *
     * Hors groupe `dashboard.client` : appelé par des balises <img>/<video> qui
     * ne peuvent PAS émettre le header custom. Sert INLINE (Content-Type auto,
     * Range supporté pour le streaming vidéo). Lecture seule, fichiers terminés.
     */
    public function raw(Transfer $transfer): Response
    {
        if ($transfer->direction !== Transfer::TO_PC || $transfer->status !== Transfer::COMPLETED) {
            abort(404);
        }

        $path = InboxLocator::fromConfig()
            ->locate($transfer->stored_name ?: $transfer->filename);

        abort_if($path === null, 404);

        return response()->file($path);
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

    /**
     * Catégorie d'un fichier : d'abord le préfixe du stored_name (rangement
     * bridge), sinon déduite de l'extension (anciens fichiers plats).
     */
    private function category(?string $storedName, ?string $filename): string
    {
        $name = (string) $storedName;
        if (str_starts_with($name, 'photos/')) {
            return 'photos';
        }
        if (str_starts_with($name, 'video/')) {
            return 'video';
        }
        if (str_starts_with($name, 'fichiers/')) {
            return 'fichiers';
        }

        $ext = strtolower(pathinfo($filename ?: $name, PATHINFO_EXTENSION));
        if (in_array($ext, self::IMAGE_EXTS, true)) {
            return 'photos';
        }
        if (in_array($ext, self::VIDEO_EXTS, true)) {
            return 'video';
        }

        return 'fichiers';
    }
}
