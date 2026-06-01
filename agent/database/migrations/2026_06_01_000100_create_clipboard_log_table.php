<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S5 — journal du presse-papier synchronisé (CDC module « Presse-papier »).
 *
 * Garde les N derniers contenus échangés (historique + copy-back côté tél).
 * `device_id` nullable sans FK : on conserve la trace même si le device est
 * révoqué/supprimé. Le `hash` sert à l'anti-boucle et à la déduplication.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('clipboard_log', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->text('content');
            $table->string('hash', 64)->comment('sha256 du contenu (anti-boucle + dédup)');
            $table->string('origin', 16)->comment('phone | pc');
            $table->timestamp('created_at')->useCurrent();

            $table->index('device_id');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('clipboard_log');
    }
};
