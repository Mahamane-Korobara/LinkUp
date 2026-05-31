<?php

namespace App\Services\Pairing;

use App\Models\Device;
use App\Services\Crypto\KeyManager;
use SodiumException;

/**
 * Validation et persistance du handshake de pairing (S2.J3).
 *
 * Le tel envoie : `tel_public_key`, `otp`, `signature(otp || tel_pubkey)`.
 * On valide en 3 étapes — chaque échec retourne une raison codifiée.
 */
class PairingHandshakeService
{
    public function __construct(
        private readonly PairingService $otpService,
        private readonly KeyManager $keyManager,
    ) {
    }

    /**
     * Valide la requête de handshake. Retourne le Device créé en pending
     * (status `approved=false`), ou throw une HandshakeRejected.
     *
     * @throws HandshakeRejected
     */
    /**
     * @param array{model?: ?string, platform?: ?string, os_version?: ?string} $metadata
     *        Infos d'affichage du tél (device_info_plus). Purement informatif.
     */
    public function handshake(
        string $telPublicKeyBase64,
        string $otp,
        string $signatureBase64,
        ?string $deviceName = null,
        array $metadata = [],
    ): Device {
        $this->validatePublicKey($telPublicKeyBase64);

        if (!$this->otpService->consumeOtp($otp)) {
            throw new HandshakeRejected('otp_invalid', 'OTP inconnu, déjà utilisé, ou expiré.');
        }

        if (!$this->verifySignature($telPublicKeyBase64, $otp, $signatureBase64)) {
            throw new HandshakeRejected(
                'signature_invalid',
                'La signature ne correspond pas à la clé publique du téléphone.',
            );
        }

        // Si ce telephone est deja paire et actif, on retourne l'existant
        // au lieu d'en creer un doublon. C'est le cas reconnexion auto S2.J5.
        $existing = Device::query()
            ->where('public_key', $telPublicKeyBase64)
            ->whereNull('revoked_at')
            ->first();

        $meta = $this->sanitizeMetadata($metadata);

        if ($existing !== null) {
            // Re-pairing : on rafraîchit l'horodatage ET les métadonnées (le tel
            // a pu changer d'OS / de nom depuis le dernier appairage).
            $existing->forceFill(['paired_at' => now(), ...$meta])->save();
            return $existing;
        }

        return Device::create([
            'name' => $deviceName ?? $this->defaultDeviceName(),
            'public_key' => $telPublicKeyBase64,
            'fingerprint_sha256' => $this->fingerprintOf($telPublicKeyBase64),
            'approved' => false,
            'paired_at' => now(),
            ...$meta,
        ]);
    }

    /**
     * Ne garde que les clés de métadonnées connues, tronquées, sans valeurs
     * vides → on n'écrase pas un champ existant avec du null au re-pairing.
     *
     * @param array<string, mixed> $metadata
     * @return array<string, string>
     */
    private function sanitizeMetadata(array $metadata): array
    {
        $out = [];
        foreach (['model', 'platform', 'os_version'] as $key) {
            $value = $metadata[$key] ?? null;
            if (is_string($value) && trim($value) !== '') {
                $out[$key] = mb_substr(trim($value), 0, 255);
            }
        }
        return $out;
    }

    /**
     * Verifie qu'une cle publique base64 fait bien 32 bytes (Ed25519).
     * @throws HandshakeRejected
     */
    private function validatePublicKey(string $base64): void
    {
        $raw = base64_decode($base64, true);
        if ($raw === false || strlen($raw) !== SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES) {
            throw new HandshakeRejected(
                'public_key_invalid',
                'Clé publique du téléphone invalide (attendu : base64 de 32 bytes).',
            );
        }
    }

    /**
     * Verifie : signature(otp || tel_pubkey) == valid (avec tel_pubkey).
     */
    private function verifySignature(
        string $telPublicKeyBase64,
        string $otp,
        string $signatureBase64,
    ): bool {
        $message = $otp . $telPublicKeyBase64;
        try {
            return $this->keyManager->verify(
                message: $message,
                signatureB64: $signatureBase64,
                publicKeyB64: $telPublicKeyBase64,
            );
        } catch (SodiumException) {
            return false;
        }
    }

    /**
     * Empreinte SHA-256 courte (8 hex) — affichee dans le popup approbation.
     * @throws HandshakeRejected
     */
    public function fingerprintOf(string $publicKeyBase64): string
    {
        $raw = base64_decode($publicKeyBase64, true);
        if ($raw === false) {
            throw new HandshakeRejected('public_key_invalid', 'Clé publique non décodable.');
        }
        return substr(hash('sha256', $raw), 0, 8);
    }

    private function defaultDeviceName(): string
    {
        return 'Téléphone Linkup ' . now()->format('Y-m-d H:i');
    }
}
