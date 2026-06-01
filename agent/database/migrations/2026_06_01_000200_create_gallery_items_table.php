<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S6 — index de la galerie distante (CDC module « Galerie »).
 *
 * Le téléphone pousse les MÉTADONNÉES de ses photos/vidéos (pas les originaux),
 * + une vignette par item (fichier sur disque, `has_thumb`). Le dashboard PC
 * parcourt cet index ; l'import des originaux passe par le module transfert (S4).
 *
 * Clé d'unicité (device_id, media_id) : `media_id` = identifiant MediaStore
 * stable côté tél → un re-scan met à jour au lieu de dupliquer.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gallery_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->string('media_id', 191);
            $table->string('mime', 64);
            $table->unsignedBigInteger('size')->default(0);
            $table->timestamp('taken_at')->nullable();
            $table->unsignedInteger('width')->nullable();
            $table->unsignedInteger('height')->nullable();
            $table->boolean('has_thumb')->default(false);
            $table->timestamps();

            $table->unique(['device_id', 'media_id']);
            $table->index(['device_id', 'taken_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gallery_items');
    }
};
