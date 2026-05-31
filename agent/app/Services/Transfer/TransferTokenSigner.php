<?php

namespace App\Services\Transfer;

/**
 * Émet un token d'upload éphémère, lié à UN transfert (S4.J3).
 *
 * Le tél reçoit ce token à l'initiate et POST ses chunks DIRECTEMENT au bridge
 * Python (rapide, PHP ne manipule pas les octets). Le bridge le valide sans
 * round-trip : token = base64url(HMAC-SHA256(transfer_id, secret partagé)), où
 * le secret est celui déjà partagé Laravel↔bridge (LINKUP_BRIDGE_AGENT_TOKEN).
 *
 * Portée : le token n'autorise QUE le transfer_id signé — il ne donne pas accès
 * au token agent complet ni aux autres transferts.
 */
class TransferTokenSigner
{
    public function __construct(
        private readonly string $sharedSecret,
    ) {
    }

    public function sign(string $transferId): string
    {
        $mac = hash_hmac('sha256', $transferId, $this->sharedSecret, true);

        // base64url sans padding — identique à l'encodage Python côté bridge.
        return rtrim(strtr(base64_encode($mac), '+/', '-_'), '=');
    }
}
