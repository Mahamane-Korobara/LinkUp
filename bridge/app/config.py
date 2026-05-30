from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="LINKUP_BRIDGE_")

    host: str = "127.0.0.1"
    port: int = 8765
    reverb_port: int = 8080
    agent_token: str = "dev-shared-token-change-me"
    transfers_dir: str = "~/Linkup/Inbox"
    downloads_dir: str = "~/Linkup/Downloads"
    log_level: str = "INFO"
    mdns_heartbeat_interval_seconds: float = 5.0
    mdns_stale_after_seconds: float = 15.0
    mdns_healthcheck_timeout_seconds: float = 2.0


settings = Settings()
