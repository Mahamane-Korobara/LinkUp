<?php

namespace App\Services\Pairing;

use App\Events\DeviceApproved;
use App\Models\Device;
use App\Models\DeviceToken;
use App\Support\RandomToken;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

/**
 * S2.J4 — approbation / refus d'un device + émission du token persistant.
 *
 * Règles :
 * - approve() : flippe `approved`, horodate, broadcast DeviceApproved.
 * - remove()  : SUPPRIME le device (refus d'un pending OU révocation d'un
 *   approuvé). Un device refusé/révoqué ne sert plus à rien : on l'efface au
 *   lieu de garder une ligne « refusé » dans le dashboard. Les tokens partent
 *   en cascade ; le tél concerné le découvre via un poll 404 (pending) ou un
 *   401 (approuvé, device + token disparus).
 * - issueTokenOnce() : génère un token 32 bytes UNE seule fois par device,
 *   stocke uniquement son hash argon2id, renvoie le token en clair (jamais
 *   re-récupérable). Appelé par la poll du tel après approbation.
 */
class DeviceApprovalService
{
    /**
     * Délai max d'attente d'approbation. Au-delà, un device pending est
     * automatiquement révoqué (le PC n'a jamais validé l'empreinte).
     */
    public const APPROVAL_TTL_SECONDS = 120;

    /**
     * Vrai si le device est en attente depuis plus que le TTL d'approbation.
     */
    public function isStalePending(Device $device): bool
    {
        return !$device->approved
            && $device->revoked_at === null
            && $device->paired_at !== null
            && $device->paired_at->lt(now()->subSeconds(self::APPROVAL_TTL_SECONDS));
    }

    /**
     * Supprime en masse les devices pending expirés. Renvoie le nombre supprimé.
     * Appelé paresseusement avant de lister / poller (pas de scheduler en S2).
     */
    public function expireStalePending(): int
    {
        return Device::query()
            ->whereNull('revoked_at')
            ->where('approved', false)
            ->where('paired_at', '<', now()->subSeconds(self::APPROVAL_TTL_SECONDS))
            ->delete();
    }

    /**
     * Approuve un device pending. Idempotent : ré-approuver un device déjà
     * approuvé ne change rien et ne re-broadcast pas.
     *
     * @throws DeviceNotApprovable si le device est révoqué.
     */
    public function approve(Device $device): Device
    {
        if ($device->revoked_at !== null) {
            throw new DeviceNotApprovable('Device révoqué : impossible à approuver.');
        }
        if ($device->approved) {
            return $device;
        }

        $device->forceFill([
            'approved' => true,
            'approved_at' => now(),
        ])->save();

        // Notification best-effort : un Reverb indisponible ne doit pas faire
        // échouer l'approbation (le tel récupère son statut via la poll).
        try {
            DeviceApproved::dispatch($device);
        } catch (\Throwable $e) {
            Log::warning('Broadcast DeviceApproved échoué (approbation OK quand même): ' . $e->getMessage());
        }

        return $device;
    }

    /**
     * Refuse (pending) ou révoque (approuvé) un device : suppression complète.
     * Les tokens partent en cascade (FK). Idempotent : supprimer un device déjà
     * absent ne fait rien.
     */
    public function remove(Device $device): void
    {
        $device->delete();
    }

    /**
     * Émet le token persistant du device si pas déjà fait. Renvoie le token
     * en clair (à transmettre au tel) au premier appel, ou null si un token
     * a déjà été émis.
     */
    public function issueTokenOnce(Device $device): ?string
    {
        if ($device->tokens()->exists()) {
            return null;
        }

        $plain = RandomToken::urlSafe(32);

        DeviceToken::create([
            'device_id' => $device->id,
            // argon2id explicite (T2.19), indépendant du driver de hash par défaut.
            'token_hash' => Hash::driver('argon2id')->make($plain),
        ]);

        return $plain;
    }
}
