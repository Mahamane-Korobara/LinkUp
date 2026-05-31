<?php

namespace App\Services\Pairing;

use App\Events\DeviceApproved;
use App\Models\Device;
use App\Models\DeviceToken;
use Illuminate\Support\Facades\Hash;

/**
 * S2.J4 — approbation / refus d'un device + émission du token persistant.
 *
 * Règles :
 * - approve() : flippe `approved`, horodate, broadcast DeviceApproved.
 * - reject()  : pose `revoked_at`, le device ne pourra plus se reconnecter.
 * - issueTokenOnce() : génère un token 32 bytes UNE seule fois par device,
 *   stocke uniquement son hash argon2id, renvoie le token en clair (jamais
 *   re-récupérable). Appelé par la poll du tel après approbation.
 */
class DeviceApprovalService
{
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

        DeviceApproved::dispatch($device);

        return $device;
    }

    /**
     * Refuse / révoque un device. Idempotent.
     */
    public function reject(Device $device): Device
    {
        if ($device->revoked_at !== null) {
            return $device;
        }

        $device->forceFill([
            'approved' => false,
            'revoked_at' => now(),
        ])->save();

        return $device;
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

        $plain = $this->generateToken();

        DeviceToken::create([
            'device_id' => $device->id,
            // argon2id explicite (T2.19), indépendant du driver de hash par défaut.
            'token_hash' => Hash::driver('argon2id')->make($plain),
        ]);

        return $plain;
    }

    /**
     * 32 octets aléatoires en base64url.
     */
    private function generateToken(): string
    {
        return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }
}
