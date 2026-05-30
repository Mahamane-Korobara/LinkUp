<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S2.J2 — table des OTPs de pairing.
 *
 * Chaque QR généré crée un OTP unique de 60 secondes. Quand le tel scanne
 * et envoie l'OTP, on le consomme une seule fois (anti-rejeu) en passant
 * `consumed_at = now()`. Au-delà de la TTL, l'OTP est rejeté même s'il
 * n'a pas été consommé.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pairing_otps', function (Blueprint $table) {
            $table->id();
            $table->string('token', 64)->unique();
            $table->timestamp('expires_at');
            $table->timestamp('consumed_at')->nullable();
            $table->timestamps();

            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pairing_otps');
    }
};
