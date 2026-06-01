<?php

namespace App\Services\Crypto;

use RuntimeException;

/**
 * Gestionnaire de la paire de clés Ed25519 de l'agent Linkup (PC).
 *
 * - Génère une paire au premier appel à `ensureKeyPair()`
 * - Stocke base64 dans `~/.linkup/keys/agent_ed25519.{pub,sec}`
 * - Le `.sec` est chmod 600 (lisible seulement par le user owner)
 * - Le dossier `~/.linkup/keys/` est chmod 700
 *
 * S2.J1 — base pour le handshake Noise IK (S2.J3) et la signature des
 * messages broadcast Reverb (S3).
 */
class KeyManager
{
    private const KEY_DIR = '.linkup/keys';
    private const PUB_FILE = 'agent_ed25519.pub';
    private const SEC_FILE = 'agent_ed25519.sec';

    public function __construct(
        private readonly string $homeDir,
    ) {
    }

    /**
     * Garantit qu'une paire existe ; la génère sinon.
     * @return array{public: string, secret: string} (base64)
     */
    public function ensureKeyPair(): array
    {
        if ($this->exists()) {
            return $this->load();
        }
        return $this->generate();
    }

    /**
     * Génère une nouvelle paire Ed25519 et l'écrit sur disque.
     * Écrase toute paire existante (rarement souhaitable — utiliser ensureKeyPair).
     */
    public function generate(): array
    {
        $kp = sodium_crypto_sign_keypair();
        $public = base64_encode(sodium_crypto_sign_publickey($kp));
        $secret = base64_encode(sodium_crypto_sign_secretkey($kp));

        $this->ensureDir();
        file_put_contents($this->pubPath(), $public);
        file_put_contents($this->secPath(), $secret);
        chmod($this->secPath(), 0600);

        return ['public' => $public, 'secret' => $secret];
    }

    /**
     * Charge la paire existante. Throws si absente.
     */
    public function load(): array
    {
        if (!$this->exists()) {
            throw new RuntimeException(
                "Paire Ed25519 introuvable dans {$this->keyDirPath()}. "
                . 'Appeler ensureKeyPair() pour la générer.'
            );
        }
        return [
            'public' => trim((string) file_get_contents($this->pubPath())),
            'secret' => trim((string) file_get_contents($this->secPath())),
        ];
    }

    /** Renvoie juste la clé publique base64 — utile pour le QR pairing. */
    public function publicKey(): string
    {
        return $this->ensureKeyPair()['public'];
    }

    /**
     * Signe un message avec la clé privée locale.
     * Retourne la signature détachée en base64.
     */
    public function sign(string $message): string
    {
        $secret = base64_decode($this->ensureKeyPair()['secret'], true);
        if ($secret === false) {
            throw new RuntimeException('Clé secrète corrompue (base64 invalide).');
        }
        return base64_encode(sodium_crypto_sign_detached($message, $secret));
    }

    /**
     * Vérifie une signature contre une clé publique (base64).
     * Utile pour valider des messages venant d'un device pairé.
     */
    public function verify(string $message, string $signatureB64, string $publicKeyB64): bool
    {
        $signature = base64_decode($signatureB64, true);
        $publicKey = base64_decode($publicKeyB64, true);
        if ($signature === false || $publicKey === false) {
            return false;
        }
        try {
            return sodium_crypto_sign_verify_detached($signature, $message, $publicKey);
        } catch (\SodiumException) {
            return false;
        }
    }

    /** Empreinte SHA-256 courte (8 hex chars) de la clé publique locale — affichage QR popup. */
    public function fingerprint(): string
    {
        return $this->fingerprintOf($this->publicKey());
    }

    /**
     * Empreinte SHA-256 courte (8 hex chars) d'une clé publique Ed25519 base64.
     *
     * Calcul centralisé du fingerprint (évite la duplication avec
     * PairingHandshakeService, qui délègue ici). Throws si base64 invalide.
     */
    public function fingerprintOf(string $publicKeyBase64): string
    {
        $raw = base64_decode($publicKeyBase64, true);
        if ($raw === false) {
            throw new RuntimeException('Clé publique non décodable (base64 invalide).');
        }
        return substr(hash('sha256', $raw), 0, 8);
    }

    public function exists(): bool
    {
        return is_file($this->pubPath()) && is_file($this->secPath());
    }

    private function ensureDir(): void
    {
        $dir = $this->keyDirPath();
        if (!is_dir($dir)) {
            if (!mkdir($dir, 0700, true) && !is_dir($dir)) {
                throw new RuntimeException("Impossible de créer $dir");
            }
        }
        chmod($dir, 0700);
    }

    private function keyDirPath(): string
    {
        return rtrim($this->homeDir, '/') . '/' . self::KEY_DIR;
    }

    private function pubPath(): string
    {
        return $this->keyDirPath() . '/' . self::PUB_FILE;
    }

    private function secPath(): string
    {
        return $this->keyDirPath() . '/' . self::SEC_FILE;
    }
}
