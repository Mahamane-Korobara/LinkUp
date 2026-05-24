<?php

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
