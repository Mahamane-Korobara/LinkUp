<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'linkup_bridge' => [
        'base_url' => env('LINKUP_BRIDGE_BASE_URL', 'http://127.0.0.1:8765'),
        // Pas de défaut devinable : DOIT être identique au LINKUP_BRIDGE_AGENT_TOKEN
        // du bridge. Vide si non configuré → TransferTokenSigner refuse de signer
        // et le bridge (qui exige un vrai token) renvoie 401.
        'token' => env('LINKUP_BRIDGE_AGENT_TOKEN', ''),
        'timeout_seconds' => env('LINKUP_BRIDGE_TIMEOUT_SECONDS', 2),
    ],

    'linkup' => [
        // Dossier racine où Linkup stocke ses clés Ed25519, transferts, etc.
        // Par défaut : $HOME du user qui lance Laravel. Overridable via .env
        // pour les tests, conteneurs, ou installations multi-comptes.
        //
        // IMPORTANT : on utilise getenv('HOME'), PAS $_SERVER['HOME'].
        // `php artisan serve` (php -S) ne peuple PAS $_SERVER['HOME'] dans le
        // contexte d'une requête HTTP → la valeur retombait sur sys_get_temp_dir()
        // (/tmp), faisant générer une paire de clés DIFFÉRENTE selon le contexte
        // (CLI vs HTTP vs pairing) → empreintes incohérentes. getenv('HOME') lit
        // l'environnement réel du process, hérité du shell, et est stable partout.
        'home_dir' => env('LINKUP_HOME_DIR', getenv('HOME') ?: sys_get_temp_dir() . '/linkup'),

        // Port HTTP Laravel mis dans le QR de pairing (cf. ADR-002 : le tel
        // attaque Laravel pour le handshake, pas le bridge).
        'pairing_port' => env('LINKUP_PAIRING_PORT', 8000),

        // Dossier des fichiers reçus (= LINKUP_BRIDGE_TRANSFERS_DIR côté bridge).
        // Laravel et le bridge tournent sur le MÊME PC/user, donc Laravel peut
        // lire l'inbox directement pour servir un fichier au tél (download).
        // Depuis S6.6 : les fichiers reçus sont rangés par catégorie sous
        // <inbox>/{photos,video,fichiers}/ (cf. bridge TransferService).
        'inbox' => env('LINKUP_INBOX_DIR', (getenv('HOME') ?: sys_get_temp_dir()) . '/Linkup/Transfert'),

        // Ancien dossier plat (avant S6.6) : fouillé en fallback pour que les
        // fichiers reçus AVANT la migration restent ouvrables/prévisualisables.
        'inbox_legacy' => env('LINKUP_INBOX_LEGACY_DIR', (getenv('HOME') ?: sys_get_temp_dir()) . '/Linkup/Inbox'),

        // S6 — dossier des fichiers que le PC envoie VERS le tél (sens to_phone).
        // Le dashboard y dépose les fichiers choisis ; le tél les télécharge.
        'outbox' => env('LINKUP_OUTBOX_DIR', (getenv('HOME') ?: sys_get_temp_dir()) . '/Linkup/Outbox'),
    ],

];
