<?php

namespace App\Providers;

use App\Services\Crypto\KeyManager;
use App\Services\Transfer\TransferTokenSigner;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // KeyManager Ed25519 singleton — la paire de clés est paresseusement
        // créée au premier appel à publicKey()/sign() (cf. ensureKeyPair()).
        $this->app->singleton(KeyManager::class, function ($app) {
            return new KeyManager(
                homeDir: (string) config('services.linkup.home_dir'),
            );
        });

        // Signe les tokens d'upload par-transfert avec le secret partagé bridge.
        $this->app->singleton(TransferTokenSigner::class, function ($app) {
            return new TransferTokenSigner(
                sharedSecret: (string) config('services.linkup_bridge.token'),
            );
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Plafond générique par IP. Large à dessein : le dashboard local (une
        // seule IP loopback) poll plusieurs endpoints toutes les 2-3 s, parfois
        // sur plusieurs onglets. 300/min laisse de la marge tout en bornant
        // l'abus (un flood se compte en milliers/min).
        RateLimiter::for('api', fn (Request $r) => Limit::perMinute(300)->by($r->ip()));

        // Pairing public, plus serré : borne le flooding de /pairing/poll (qui
        // journalise chaque signature invalide → sinon amplification de la table
        // d'audit) et les tentatives de /pairing/handshake. 60/min couvre la
        // cadence légitime du tél (poll toutes les 2 s = 30/min) avec 2× de marge.
        RateLimiter::for('pairing', fn (Request $r) => Limit::perMinute(60)->by($r->ip()));
    }
}
