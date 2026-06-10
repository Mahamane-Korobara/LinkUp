<?php

namespace App\Http\Controllers\Clipboard;

use App\Http\Controllers\Controller;
use App\Models\ClipboardEntry;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use App\Services\Clipboard\ClipboardService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * S5 — presse-papier + lien rapide, authentifié par le token device.
 *
 * Le tél pousse/récupère du texte ; Laravel journalise (anti-boucle) et délègue
 * l'accès réel au presse-papier de l'OS au bridge Python.
 */
class ClipboardController extends Controller
{
    public function __construct(
        private readonly ClipboardService $clipboard,
    ) {
    }

    /**
     * POST /api/clipboard — le tél pousse un contenu copié → écrit dans le
     * presse-papier du PC. Anti-boucle : un doublon récent est ignoré (deduped).
     */
    public function push(Request $request, BridgeClient $bridge): JsonResponse
    {
        $validated = $request->validate([
            'content' => 'required|string|max:1048576', // 1 Mo
        ]);

        // On écrit D'ABORD sur le presse-papier du PC : si ça échoue (ex. aucun
        // outil installé), on renvoie l'erreur SANS journaliser d'entrée fantôme.
        try {
            $bridge->writeClipboard($validated['content']);
        } catch (BridgeUnavailableException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }

        $entry = $this->clipboard->receive(
            $this->device($request),
            $validated['content'],
            ClipboardService::ORIGIN_PHONE,
        );

        if ($entry === null) {
            return response()->json(['ok' => true, 'deduped' => true]);
        }

        return response()->json(['ok' => true, 'id' => $entry->id]);
    }

    /**
     * GET /api/clipboard — historique récent du presse-papier (ce device).
     */
    public function index(Request $request): JsonResponse
    {
        $items = $this->clipboard->recent($this->device($request))
            ->map(fn (ClipboardEntry $e) => [
                'id' => $e->id,
                'content' => $e->content,
                'origin' => $e->origin,
                'created_at' => $e->created_at?->toIso8601String(),
            ]);

        return response()->json(['items' => $items]);
    }

    /**
     * GET /api/clipboard/pc — lit le presse-papier ACTUEL du PC (copy-back tél).
     */
    public function pc(Request $request, BridgeClient $bridge): JsonResponse
    {
        try {
            $data = $bridge->readClipboard();
        } catch (BridgeUnavailableException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }

        $content = (string) ($data['text'] ?? '');
        if ($content !== '') {
            // Journalise (origin=pc) ; l'anti-boucle évite un doublon si ce
            // contenu vient justement d'être poussé par le tél.
            $this->clipboard->receive($this->device($request), $content, ClipboardService::ORIGIN_PC);
        }

        return response()->json(['text' => $content]);
    }

    /**
     * POST /api/link/open — ouvre un lien http(s) dans le navigateur du PC.
     */
    public function openLink(Request $request, BridgeClient $bridge): JsonResponse
    {
        $validated = $request->validate([
            // Double barrière avec la validation de schéma côté bridge : on
            // refuse ici tout ce qui n'est pas http(s) (file://, javascript:…).
            'url' => 'required|string|max:2048|starts_with:http://,https://',
        ]);

        try {
            $result = $bridge->openLink($validated['url']);
        } catch (BridgeUnavailableException $e) {
            return response()->json(['message' => $e->getMessage()], 503);
        }

        return response()->json(['ok' => true, 'url' => $result['url'] ?? $validated['url']]);
    }
}
