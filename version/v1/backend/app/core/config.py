from __future__ import annotations

import os
from functools import lru_cache


def _split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


class Settings:
    app_env: str
    cors_origins: list[str]
    database_url: str | None
    log_level: str

    def __init__(self) -> None:
        self.app_env = os.getenv("APP_ENV", "production")
        self.cors_origins = _split_csv(os.getenv("CORS_ORIGINS"))
        self.database_url = os.getenv("DATABASE_URL")
        self.log_level = os.getenv("LOG_LEVEL", "info")


@lru_cache
def get_settings() -> Settings:
    return Settings()
