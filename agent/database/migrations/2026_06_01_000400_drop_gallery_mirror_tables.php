<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

/**
 * S6 — abandon du modèle « galerie distante » (index + vignettes mirrorées).
 *
 * Remplacé par l'envoi sélectif depuis le tél : l'utilisateur choisit ses photos
 * et les pousse via le module transfert (table `transfers`). Plus aucun index de
 * galerie côté PC → on supprime les tables devenues mortes.
 *
 * `dropIfExists` : no-op sur une base fraîche (les migrations de création ont été
 * retirées), nettoyage réel sur les bases de dev qui les avaient déjà.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::dropIfExists('gallery_import_requests');
        Schema::dropIfExists('gallery_items');
    }

    public function down(): void
    {
        // Irréversible par choix : le modèle mirror est abandonné, pas suspendu.
    }
};
