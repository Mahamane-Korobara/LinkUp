<?php

use App\Services\MdnsAnnouncer;
use App\Events\PingEvent;
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

Route::get('/agent/info', function (MdnsAnnouncer $mdns) {
    $info = $mdns->localInfo();

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

Route::get('/mdns/services', function (MdnsAnnouncer $mdns) {
    return response()->json($mdns->discoveredServices());
});

Route::post('/ping', function (Request $request) {
    $message = $request->input('message', 'pong');
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
