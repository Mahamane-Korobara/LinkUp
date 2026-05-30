<?php

namespace App\Http\Controllers;

use App\Events\PingEvent;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PingController extends Controller
{
    /**
     * POST /api/ping — émet un PingEvent broadcasté sur Reverb.
     * Utile pour smoke-tester le wiring temps réel end-to-end.
     */
    public function send(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'message' => 'sometimes|string|max:500',
        ]);
        $message = $validated['message'] ?? 'pong';
        event(new PingEvent($message));

        return response()->json([
            'broadcasted' => true,
            'channel' => 'linkup-system',
            'event' => 'ping',
            'message' => $message,
        ]);
    }
}
