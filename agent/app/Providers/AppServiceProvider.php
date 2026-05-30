<?php

namespace App\Providers;

use App\Services\Crypto\KeyManager;
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
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
