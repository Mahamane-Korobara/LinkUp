<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S3.J3 — journal d'audit sécurité (CDC §15).
 *
 * Trace toutes les tentatives rejetées (handshake invalide, signature poll
 * forgée, accès dashboard non autorisé, etc.). `device_id` est nullable et
 * SANS contrainte FK : un rejet peut concerner un device inexistant ou déjà
 * supprimé, on ne veut pas perdre la trace.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('security_audit', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id')->nullable();
            $table->string('event')->comment('ex. handshake_rejected, poll_signature_invalid');
            $table->json('payload')->nullable();
            $table->string('ip', 45)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index('event');
            $table->index('device_id');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('security_audit');
    }
};
