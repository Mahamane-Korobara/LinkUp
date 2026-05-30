<?php

use App\Events\PingEvent;
use App\Services\BridgeClient;
use App\Services\BridgeUnavailableException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'service' => 'linkup-agent',
        'version' => config('app.version', '0.1.0'),
        'time' => now()->toIso8601String(),
    ]);
});

Route::get('/agent/info', function (BridgeClient $bridge) {
    try {
        $info = $bridge->localInfo();
    } catch (BridgeUnavailableException $e) {
        return response()->json(['error' => $e->getMessage()], 503);
    }

    return response()->json([
        'name' => $info['instance_name'] ?? config('app.name'),
        'fingerprint' => $info['fingerprint'] ?? 'pending',
        'agent_id' => $info['agent_id'] ?? null,
        'version' => $info['version'] ?? config('app.version', '0.1.0'),
        'reverb_port' => $info['port'] ?? null,
        'bridge_port' => $info['bridge_port'] ?? null,
        'source' => 'bridge',
    ]);
});

Route::get('/mdns/services', function (BridgeClient $bridge) {
    try {
        return response()->json($bridge->discoveredServices());
    } catch (BridgeUnavailableException $e) {
        return response()->json(['error' => $e->getMessage()], 503);
    }
});

Route::post('/ping', function (Request $request) {
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
});

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
