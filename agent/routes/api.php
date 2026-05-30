<?php

use App\Http\Controllers\AgentInfoController;
use App\Http\Controllers\PingController;
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

Route::get('/agent/info', [AgentInfoController::class, 'show']);
Route::get('/mdns/services', [AgentInfoController::class, 'services']);

Route::post('/ping', [PingController::class, 'send']);

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
