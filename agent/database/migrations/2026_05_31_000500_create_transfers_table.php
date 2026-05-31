<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S4.J2 (CDC §15) — métadonnées d'un transfert de fichier.
 *
 * Les chunks binaires sont stockés par le bridge Python (~/.linkup/transfers) ;
 * cette table ne garde que l'état d'orchestration côté Laravel.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('transfers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('device_id')->constrained('devices')->cascadeOnDelete();
            $table->string('filename');
            $table->unsignedBigInteger('size');
            $table->string('sha256', 64)->nullable()->comment('hex SHA-256 du fichier complet');
            $table->string('direction')->comment('to_pc (tel→PC) | to_phone (PC→tel)');
            $table->string('status')->default('pending')
                ->comment('pending | uploading | completed | failed | cancelled');
            $table->unsignedInteger('total_chunks')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();

            $table->index('device_id');
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('transfers');
    }
};
