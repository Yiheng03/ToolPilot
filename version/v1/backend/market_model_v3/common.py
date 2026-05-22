import json
import os
from datetime import date, datetime
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[2]
TOOLSQL_DIR = ROOT_DIR.parent
SQL_PATH = ROOT_DIR / "backend" / "sql" / "20260522_create_market_model_v3_quant_tables.sql"
MODEL_DIR = ROOT_DIR / "backend" / "models" / "market_model_v3"
REPORT_DIR = ROOT_DIR / "backend" / "reports"
REPORT_PATH = REPORT_DIR / "market_model_v3_quant_signal_implementation_report.md"
MODEL_NAME = "market_model_v3_quant_signal"
MODEL_VERSION = "v3_20260522"
HORIZONS = [7, 30, 90]
MIN_HISTORY_ROWS = 180


def log(message: str) -> None:
    print(f"[market_model_v3] {message}", flush=True)


def load_env() -> None:
    for path in [TOOLSQL_DIR / ".env", ROOT_DIR / ".env"]:
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def connect(row_factory=dict_row):
    load_env()
    return psycopg.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "postgres"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD", "sinomach"),
        row_factory=row_factory,
    )


def ensure_dirs() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)


def ensure_tables() -> dict[str, int]:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(SQL_PATH.read_text(encoding="utf-8"))
            stats: dict[str, int] = {}
            for table in [
                "market_quant_features",
                "market_pair_features",
                "market_model_versions",
                "market_quant_forecasts",
            ]:
                cur.execute(f"SELECT COUNT(*) AS count FROM {table}")
                stats[table] = int(cur.fetchone()["count"])
        conn.commit()
    log(f"tables ready: {stats}")
    return stats


def json_default(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return str(value)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, default=json_default), encoding="utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def query_dataframe(sql: str, params: tuple = ()):
    import pandas as pd

    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
    return pd.DataFrame(rows)
