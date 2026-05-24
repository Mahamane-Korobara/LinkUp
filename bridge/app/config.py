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


settings = Settings()
