<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S2 — métadonnées du téléphone affichées sur le dashboard (page devices).
 *
 * Le tel les envoie au handshake (device_info_plus) ; elles sont purement
 * informatives (aucune valeur de sécurité), d'où le `nullable` partout pour
 * rester rétro-compatible avec un tel qui ne les fournit pas.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $table->string('model')->nullable()->after('name')->comment('ex. Google Pixel 7');
            $table->string('platform')->nullable()->after('model')->comment('Android / iOS');
            $table->string('os_version')->nullable()->after('platform')->comment('ex. Android 14');
        });
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $table->dropColumn(['model', 'platform', 'os_version']);
        });
    }
};
