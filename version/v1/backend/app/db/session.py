from __future__ import annotations

import psycopg
from psycopg.rows import dict_row

from app.core.config import get_settings


def get_connection(row_factory=dict_row):
    settings = get_settings()
    if not settings.database_url:
        raise RuntimeError("DATABASE_URL is required")
    return psycopg.connect(settings.database_url, row_factory=row_factory)
