<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * S4 — nom final du fichier dans l'inbox du PC (après gestion des collisions
 * côté bridge). Permet de rouvrir le fichier (« Ouvrir sur le PC »).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transfers', function (Blueprint $table) {
            $table->string('stored_name')->nullable()->after('filename');
        });
    }

    public function down(): void
    {
        Schema::table('transfers', function (Blueprint $table) {
            $table->dropColumn('stored_name');
        });
    }
};
