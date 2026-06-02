<?php

use App\Services\Clipboard\ClipboardService;
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

// S5 — purge du presse-papier journalisé de plus de 2 jours (rétention courte
// par confidentialité). La purge se fait aussi à chaque échange (cf.
// ClipboardService::receive) ; ce planificateur couvre le cas « serveur idle ».
Artisan::command('linkup:prune-clipboard', function (ClipboardService $clipboard) {
    $deleted = $clipboard->prune();
    $this->info("Entrées presse-papier purgées : {$deleted}");
})->purpose('Supprime le presse-papier journalisé expiré (> 2 jours)');

Schedule::command('linkup:prune-clipboard')->daily();
