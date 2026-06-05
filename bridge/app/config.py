from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Valeur sentinelle interdite : si quelqu'un copie .env.example sans changer le token,
# le bridge refusera de démarrer plutôt que de servir un secret connu de tout GitHub.
PLACEHOLDER_TOKEN = "change-me-to-a-random-32-bytes-base64"

# Seuil d'entropie minimale : refuse un token comme `aaaaaaaaaaaaaaaa` ou
# `abcdefghijklmnop` qui passe `min_length=16` mais reste trivialement devinable.
_MIN_UNIQUE_CHARS = 8


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="LINKUP_BRIDGE_")

    host: str = "0.0.0.0"
    port: int = Field(default=8765, ge=1, le=65535)
    reverb_port: int = Field(default=8080, ge=1, le=65535)
    # Port HTTP de l'agent Laravel (FrankenPHP). Annoncé dans /health et mDNS
    # pour que le téléphone joigne /api/agent/info sur le BON port sans le coder
    # en dur (8000 en dev, 8770 dans le bundle PC — cf. linkup-launch.sh).
    laravel_port: int = Field(default=8000, ge=1, le=65535)
    # Port du dashboard Next en DEV (3000) : exclu de la détection Dev Preview
    # (on n'expose pas le dashboard Linkup lui-même). 0 = aucun (cas du bundle,
    # où le dashboard est servi en même-origine par FrankenPHP, pas sur un port
    # séparé) → là, 3000 redevient un port utilisateur normal et reste listable.
    dashboard_port: int = Field(default=0, ge=0, le=65535)
    # Token Bearer partagé avec Laravel. Pas de valeur par défaut : refus de démarrer
    # si non configuré (cf. ADR-002 sécurité). En prod, généré par les installeurs S6.5.
    agent_token: str = Field(min_length=16)
    transfers_dir: str = "~/Linkup/Transfert"
    # Ancien dossier plat (avant le rangement par catégorie), fouillé en fallback
    # à l'ouverture pour les fichiers reçus avant la migration.
    transfers_dir_legacy: str = "~/Linkup/Inbox"
    downloads_dir: str = "~/Linkup/Downloads"
    log_level: str = "INFO"
    mdns_heartbeat_interval_seconds: float = Field(default=5.0, gt=0.5)
    mdns_stale_after_seconds: float = Field(default=15.0, gt=1.0)
    mdns_healthcheck_timeout_seconds: float = Field(default=2.0, gt=0.1)

    @field_validator("agent_token")
    @classmethod
    def _validate_token(cls, value: str) -> str:
        stripped = value.strip()
        if stripped == PLACEHOLDER_TOKEN:
            raise ValueError(
                "LINKUP_BRIDGE_AGENT_TOKEN ne peut pas être la valeur placeholder. "
                "Génère-en un nouveau : python -c 'import secrets; print(secrets.token_urlsafe(32))'"
            )
        if len(set(stripped)) < _MIN_UNIQUE_CHARS:
            raise ValueError(
                f"LINKUP_BRIDGE_AGENT_TOKEN doit contenir au moins {_MIN_UNIQUE_CHARS} "
                "caractères distincts (entropie minimale)."
            )
        return value


settings = Settings()
