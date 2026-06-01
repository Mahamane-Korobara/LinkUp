<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Models\ClipboardEntry;
use App\Services\Clipboard\ClipboardService;
use Illuminate\Http\JsonResponse;

/**
 * S5 — historique du presse-papier vu depuis le dashboard PC (auth dashboard.client).
 *
 * Lecture seule : la liste des contenus synchronisés, pour copy-back côté PC.
 */
class ClipboardController extends Controller
{
    public function __construct(
        private readonly ClipboardService $clipboard,
    ) {
    }

    /**
     * GET /api/clipboard/history — derniers contenus synchronisés (tous devices).
     */
    public function index(): JsonResponse
    {
        $items = $this->clipboard->recentAll()
            ->map(fn (ClipboardEntry $e) => [
                'id' => $e->id,
                'content' => $e->content,
                'origin' => $e->origin,
                'device_id' => $e->device_id,
                'created_at' => $e->created_at?->toIso8601String(),
            ]);

        return response()->json(['items' => $items]);
    }
}
