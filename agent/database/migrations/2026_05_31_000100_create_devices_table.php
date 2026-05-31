<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S2.J3-J4 — table des devices appairés.
 *
 * Version minimale pour S2 : ce qu'il faut pour identifier un téléphone
 * pairé + son statut d'approbation. Le CDC §15 prévoit plus de colonnes
 * (transport, last_seen, etc.) qui arriveront avec S3 (modèle complet).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name')->nullable();
            $table->string('public_key', 64)->unique()->comment('base64 Ed25519 32 bytes');
            $table->string('fingerprint_sha256', 16)->comment('8 hex chars truncated SHA-256');
            $table->boolean('approved')->default(false);
            $table->timestamp('paired_at')->nullable();
            $table->timestamp('approved_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            $table->index('approved');
            $table->index('revoked_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('devices');
    }
};
