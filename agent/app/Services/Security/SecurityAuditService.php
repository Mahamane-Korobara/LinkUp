<?php

namespace App\Services\Security;

use App\Models\SecurityAudit;
use Illuminate\Support\Facades\Log;

/**
 * S3.J3 — point d'entrée unique pour journaliser les événements sécurité.
 *
 * Centralise l'écriture dans `security_audit` (T3.9-T3.11). Best-effort : une
 * erreur d'écriture du journal ne doit JAMAIS casser la requête métier en
 * cours (on log dans le fichier Laravel en fallback).
 */
class SecurityAuditService
{
    // Événements connus — évite les magic strings dispersées.
    public const HANDSHAKE_REJECTED = 'handshake_rejected';
    public const POLL_SIGNATURE_INVALID = 'poll_signature_invalid';
    public const DASHBOARD_FORBIDDEN = 'dashboard_forbidden';
    public const DEVICE_REJECTED = 'device_rejected';
    public const DEVICE_AUTH_FAILED = 'device_auth_failed';
    // Réinitialisation complète du PC depuis le dashboard (fichiers reçus,
    // transferts, presse-papier, pairing). Geste destructeur → tracé.
    public const DATA_WIPED = 'data_wiped';
    // Requête sur une route réservée au PC local, venue d'une IP non-loopback
    // (ex. un hôte du LAN qui forge le header dashboard). Cf. LocalhostOnly.
    public const NON_LOCAL_FORBIDDEN = 'non_local_forbidden';

    /**
     * @param array<string, mixed> $payload
     */
    public function log(string $event, ?string $deviceId = null, array $payload = [], ?string $ip = null): void
    {
        try {
            SecurityAudit::create([
                'device_id' => $deviceId,
                'event' => $event,
                'payload' => $payload ?: null,
                'ip' => $ip,
            ]);
        } catch (\Throwable $e) {
            Log::warning("Audit sécurité non persisté ($event): " . $e->getMessage());
        }
    }
}
