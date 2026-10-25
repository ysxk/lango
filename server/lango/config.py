from pathlib import Path
from typing import Literal

from pydantic import SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

VOICES = ("Kore", "Puck", "Charon", "Fenrir", "Aoede")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="LANGO_", extra="ignore", hide_input_in_errors=True
    )

    environment: Literal["development", "production"] = "development"
    database_url: SecretStr = SecretStr("sqlite:///./data/lango.db")
    jwt_secret: SecretStr
    allowed_origins: list[str] = []
    google_api_key: SecretStr | None = None
    text_model: str = "gemini-3.8-flash"
    tts_model: str = "gemini-3.8-flash-lite-tts"
    live_model: str = "gemini-3.8-live"
    embedding_model: str = "gemini-embedding-001"
    default_engine: Literal["cascade", "live"] = "cascade"
    access_minutes: int = 15
    refresh_days: int = 30
    daily_minutes: int = 60
    provider_timeout_seconds: int = 120
    memory_path: str = "./data/memory"
    memory_postgres_url: SecretStr | None = None
    memory_qdrant_url: str | None = None
    memory_qdrant_api_key: SecretStr | None = None
    worker_poll_seconds: float = 2.0
    worker_lease_seconds: int = 600

    @model_validator(mode="after")
    def secure(self):
        if len(self.jwt_secret.get_secret_value()) < 32:
            raise ValueError("LANGO_JWT_SECRET must contain at least 32 characters")
        if not 1 <= self.daily_minutes <= 1440:
            raise ValueError("LANGO_DAILY_MINUTES must be between 1 and 1440")
        if not 1 <= self.access_minutes <= 60 or not 1 <= self.refresh_days <= 90:
            raise ValueError("Invalid token lifetimes")
        if not 10 <= self.provider_timeout_seconds <= 300:
            raise ValueError("Invalid provider timeout")
        if self.worker_lease_seconds < self.provider_timeout_seconds * 2:
            raise ValueError("Worker lease must exceed twice the provider timeout")
        if not 0.1 <= self.worker_poll_seconds <= 60 or self.worker_lease_seconds > 3600:
            raise ValueError("Invalid worker timing")
        if self.environment == "production":
            if not self.database_url.get_secret_value().startswith("postgresql+psycopg://"):
                raise ValueError("Production requires PostgreSQL (postgresql+psycopg://)")
            if not self.allowed_origins or any(
                not o.startswith("https://") or "*" in o for o in self.allowed_origins
            ):
                raise ValueError("Production requires explicit HTTPS origins")
            if not self.memory_postgres_url:
                raise ValueError("Production requires LANGO_MEMORY_POSTGRES_URL with pgvector")
        if any("*" in origin for origin in self.allowed_origins):
            raise ValueError("Wildcard origins are forbidden")
        return self

    def prepare_paths(self):
        url = self.database_url.get_secret_value()
        if url.startswith("sqlite:///") and not url.endswith(":memory:"):
            Path(url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
        Path(self.memory_path).mkdir(parents=True, exist_ok=True)
