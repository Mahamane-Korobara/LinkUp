<?php

use App\Services\Pairing\PairingService;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// S3.J5 (T3.18) — purge des OTPs de pairing expirés depuis plus de 5 min.
// Les OTPs restent rejetés bien avant (TTL 60 s) ; ceci nettoie juste la table.
Artisan::command('linkup:purge-otps', function (PairingService $pairing) {
    $deleted = $pairing->purgeExpired();
    $this->info("OTPs purgés : {$deleted}");
})->purpose('Supprime les OTPs de pairing expirés');

Schedule::command('linkup:purge-otps')->everyFiveMinutes();
