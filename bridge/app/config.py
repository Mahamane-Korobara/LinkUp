from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Valeur sentinelle interdite : si quelqu'un copie .env.example sans changer le token,
# le bridge refusera de démarrer plutôt que de servir un secret connu de tout GitHub.
_PLACEHOLDER_TOKEN = "change-me-to-a-random-32-bytes-base64"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="LINKUP_BRIDGE_")

    host: str = "0.0.0.0"
    port: int = Field(default=8765, ge=1, le=65535)
    reverb_port: int = Field(default=8080, ge=1, le=65535)
    # Token Bearer partagé avec Laravel. Pas de valeur par défaut : refus de démarrer
    # si non configuré (cf. ADR-002 sécurité). En prod, généré par les installeurs S6.5.
    agent_token: str = Field(min_length=16)
    transfers_dir: str = "~/Linkup/Inbox"
    downloads_dir: str = "~/Linkup/Downloads"
    log_level: str = "INFO"
    mdns_heartbeat_interval_seconds: float = Field(default=5.0, gt=0.5)
    mdns_stale_after_seconds: float = Field(default=15.0, gt=1.0)
    mdns_healthcheck_timeout_seconds: float = Field(default=2.0, gt=0.1)

    @field_validator("agent_token")
    @classmethod
    def _refuse_placeholder_token(cls, value: str) -> str:
        if value.strip() == _PLACEHOLDER_TOKEN:
            raise ValueError(
                "LINKUP_BRIDGE_AGENT_TOKEN ne peut pas être la valeur placeholder. "
                "Génère-en un nouveau : python -c 'import secrets; print(secrets.token_urlsafe(32))'"
            )
        return value


settings = Settings()
