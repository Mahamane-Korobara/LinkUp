<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Services\Maintenance\ReceivedDataWiper;
use App\Services\Security\SecurityAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Réinitialisation du PC (auth dashboard.client + local.only).
 *
 * Expose un aperçu de tout ce que les téléphones ont laissé sur ce PC, et un
 * endpoint pour TOUT effacer (fichiers reçus, transferts, presse-papier,
 * pairing). Le délai d'annulation de 5 s est géré côté dashboard : ici la
 * suppression est immédiate quand l'appel arrive.
 */
class DataController extends Controller
{
    public function __construct(
        private readonly SecurityAuditService $audit,
    ) {
    }

    /** GET /api/data/summary — ce qui sera supprimé (pour la confirmation). */
    public function summary(): JsonResponse
    {
        return response()->json(ReceivedDataWiper::fromConfig()->summary());
    }

    /** DELETE /api/data — efface tout. */
    public function destroy(Request $request): JsonResponse
    {
        $deleted = ReceivedDataWiper::fromConfig()->wipe();

        $this->audit->log(
            SecurityAuditService::DATA_WIPED,
            payload: $deleted,
            ip: $request->ip(),
        );

        return response()->json(['deleted' => $deleted]);
    }
}
