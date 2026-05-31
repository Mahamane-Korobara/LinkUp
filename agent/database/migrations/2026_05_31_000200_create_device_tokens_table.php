<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S2.J4 (T2.19) — token persistant émis à l'approbation d'un device.
 *
 * Seul le HASH argon2id du token est stocké : le token en clair n'existe
 * qu'une fois, transmis au tel à la première poll après approbation, puis
 * gardé uniquement dans le secure storage du tel. Un device n'a qu'un seul
 * token actif (révoquer = supprimer la ligne / révoquer le device).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('device_id')
                ->constrained('devices')
                ->cascadeOnDelete();
            $table->string('token_hash')->comment('argon2id hash du token 32 bytes');
            $table->timestamp('last_used_at')->nullable();
            $table->timestamps();

            $table->index('device_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
