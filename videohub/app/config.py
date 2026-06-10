from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Valeur sentinelle interdite : si quelqu'un copie .env.example sans changer le token,
# le service refuse de démarrer plutôt que de servir un secret connu de tout GitHub.
PLACEHOLDER_TOKEN = "change-me-to-a-random-32-bytes-base64"

# Seuil d'entropie minimale : refuse un token comme `aaaaaaaaaaaaaaaa` qui passe
# `min_length=16` mais reste trivialement devinable.
_MIN_UNIQUE_CHARS = 8


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="LINKUP_VIDEOHUB_")

    # Service internet-facing : derrière Apache (proxy local), on n'écoute que sur
    # la loopback du VPS. Apache termine le TLS et proxifie /video/ → 127.0.0.1:8780.
    host: str = "127.0.0.1"
    port: int = Field(default=8780, ge=1, le=65535)

    # Token Bearer statique partagé avec l'app mobile. Pas de défaut : refus de
    # démarrer si non configuré. NOTE: extractible de l'APK → pas un secret fort,
    # juste un garde-fou anti-abus casual en alpha.
    service_token: str = Field(min_length=16)

    # Clé API Google Gemini (palier gratuit) pour formater le transcript en document.
    # Vide = on saute directement au repli heuristique (le service marche sans clé).
    gemini_api_key: str = ""
    # Modèle Gemini : Flash = palier gratuit, excellent en FR. gemini-3.5-flash est
    # le Flash STABLE courant (juin 2026), éligible au palier gratuit. Surchargeable
    # via LINKUP_VIDEOHUB_GEMINI_MODEL si Google renomme/déprécie le modèle.
    gemini_model: str = "gemini-3.5-flash"

    # Fichier cookies au format Netscape (optionnel). YouTube bloque l'accès
    # anonyme depuis une IP datacenter (« Sign in to confirm you're not a bot ») :
    # fournir des cookies exportés d'un navigateur connecté débloque YouTube.
    # Vide = pas de cookies (les autres plateformes marchent quand même).
    yt_cookies_file: str = ""

    # Dossier de staging des téléchargements (nettoyé après streaming).
    tmp_dir: str = "/tmp/linkup-videohub"

    # Garde-fou anti-abus : nombre max de requêtes par IP et par minute (in-memory).
    rate_limit_per_min: int = Field(default=20, ge=1)

    # Plafond de taille de téléchargement (Mo) pour éviter qu'une vidéo énorme
    # sature le disque / la bande passante du VPS. 0 = pas de limite.
    max_download_mb: int = Field(default=512, ge=0)

    log_level: str = "INFO"

    @field_validator("service_token")
    @classmethod
    def _validate_token(cls, value: str) -> str:
        stripped = value.strip()
        if stripped == PLACEHOLDER_TOKEN:
            raise ValueError(
                "LINKUP_VIDEOHUB_SERVICE_TOKEN ne peut pas être la valeur placeholder. "
                "Génère-en un : python -c 'import secrets; print(secrets.token_urlsafe(32))'"
            )
        if len(set(stripped)) < _MIN_UNIQUE_CHARS:
            raise ValueError(
                f"LINKUP_VIDEOHUB_SERVICE_TOKEN doit contenir au moins {_MIN_UNIQUE_CHARS} "
                "caractères distincts (entropie minimale)."
            )
        return value


settings = Settings()
