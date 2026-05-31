<?php

namespace App\Providers;

use App\Services\Crypto\KeyManager;
use App\Services\Transfer\TransferTokenSigner;
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
        //
    }
}
