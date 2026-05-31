<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S4.J2 (CDC §15) — suivi des chunks reçus, pour la reprise après coupure.
 *
 * Une ligne par chunk validé (SHA-256 vérifié côté bridge). À la reprise, on
 * connaît les index déjà reçus → on ne redemande que les manquants.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('file_chunks', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('transfer_id')->constrained('transfers')->cascadeOnDelete();
            $table->unsignedInteger('chunk_index');
            $table->string('sha256', 64);
            $table->timestamp('received_at')->useCurrent();

            // Un même index n'est validé qu'une fois par transfert.
            $table->unique(['transfer_id', 'chunk_index']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('file_chunks');
    }
};
