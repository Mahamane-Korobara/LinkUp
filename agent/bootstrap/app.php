<?php

use App\Http\Middleware\AuthenticateDevice;
use App\Http\Middleware\LocalhostOnly;
use App\Http\Middleware\RequireDashboardClient;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        channels: __DIR__.'/../routes/channels.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Plafond générique par IP sur tout /api/* (limiteur défini dans
        // AppServiceProvider::boot). Les chunks lourds vont au bridge, pas ici.
        $middleware->api(append: [
            'throttle:api',
        ]);

        $middleware->alias([
            'dashboard.client' => RequireDashboardClient::class,
            'auth.device' => AuthenticateDevice::class,
            // Réservé à la loopback : ferme l'accès LAN aux routes du dashboard.
            'local.only' => LocalhostOnly::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
