<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S6.J4 — demandes d'import d'originaux.
 *
 * Le PC ne peut pas « pousser » vers le tél (c'est le tél qui se connecte). Quand
 * l'utilisateur sélectionne des médias sur le dashboard, on enregistre ici une
 * demande `requested` ; le tél la récupère en polling, uploade l'original VIA LE
 * MODULE TRANSFERT S4 (table `transfers`), puis marque la demande `done` en
 * pointant le `transfer_id` produit.
 *
 * Une seule demande active par item (unique sur gallery_item_id) : re-demander un
 * item remet juste son statut à `requested`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gallery_import_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('device_id');
            $table->uuid('gallery_item_id');
            $table->string('media_id', 191);
            $table->string('status', 16)->default('requested'); // requested|done|failed
            $table->uuid('transfer_id')->nullable();
            $table->timestamps();

            $table->unique('gallery_item_id');
            $table->index(['device_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gallery_import_requests');
    }
};
