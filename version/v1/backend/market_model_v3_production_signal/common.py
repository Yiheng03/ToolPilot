from __future__ import annotations

import json
import os
from datetime import date, datetime
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[2]
TOOLSQL_DIR = ROOT_DIR.parent
SQL_PATH = ROOT_DIR / "backend" / "sql" / "20260522_create_market_model_v3_production_signal_tables.sql"
MODEL_DIR = ROOT_DIR / "backend" / "models" / "market_model_v3_production_signal"
REPORT_DIR = ROOT_DIR / "backend" / "reports"
REPORT_PATH = REPORT_DIR / "market_model_v3_production_signal_report.md"
MODULE_DIR = ROOT_DIR / "backend" / "market_model_v3_production_signal"
MODEL_NAME = "market_model_v3_production_signal"
MODEL_VERSION = "v3_production_20260522"
BASE_QUANT_MODEL_VERSION = "v3_20260522"
HORIZONS = [7, 30, 90]

INDUSTRIAL_FACTORS = {
    "CU": ("铜", "industrial_metal"),
    "AL": ("铝", "industrial_metal"),
    "NI": ("镍", "industrial_metal"),
    "CO": ("钴", "industrial_metal"),
    "ZN": ("锌", "industrial_metal"),
    "SN": ("锡", "industrial_metal"),
    "PB": ("铅", "industrial_metal"),
    "IRON_ORE": ("铁矿石", "industrial_metal"),
}

REQUESTED_FACTORS = {
    **INDUSTRIAL_FACTORS,
    "WTI": ("WTI原油", "energy"),
    "BRENT": ("布伦特原油", "energy"),
    "NATURAL_GAS": ("天然气", "energy"),
    "GOLD": ("黄金", "precious_metal"),
    "SILVER": ("白银", "precious_metal"),
    "DXY": ("美元指数", "fx"),
    "USD_CNY": ("美元人民币", "fx"),
    "SP500": ("标普500", "equity_index"),
    "NASDAQ": ("纳斯达克", "equity_index"),
    "CSI300": ("沪深300", "equity_index"),
    "SHANGHAI_INDEX": ("上证指数", "equity_index"),
}

PANEL_FEATURE_COLUMNS = [
    "metal_code",
    "metal_return_1d",
    "metal_return_7d",
    "metal_return_30d",
    "metal_return_90d",
    "metal_volatility_30d",
    "metal_volatility_90d",
    "metal_momentum_30d",
    "metal_momentum_90d",
    "metal_zscore_90d",
    "metal_drawdown_90d",
    "pred_lgb_return_7d",
    "pred_lgb_return_30d",
    "pred_lgb_return_90d",
    "industrial_metals_return_30d",
    "industrial_metals_return_90d",
    "energy_return_30d",
    "energy_return_90d",
    "usd_return_30d",
    "usd_return_90d",
    "precious_metals_return_30d",
    "precious_metals_return_90d",
    "risk_asset_return_30d",
    "risk_asset_return_90d",
    "cu_al_ratio",
    "ni_co_ratio",
    "co_cu_ratio",
    "ni_cu_ratio",
    "sn_cu_ratio",
    "zn_al_ratio",
    "pb_al_ratio",
    "iron_ore_cu_ratio",
]


def log(message: str) -> None:
    print(f"[market_model_v3_production_signal] {message}", flush=True)


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
    MODULE_DIR.mkdir(parents=True, exist_ok=True)


def ensure_tables() -> dict[str, int]:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(SQL_PATH.read_text(encoding="utf-8"))
            stats: dict[str, int] = {}
            for table in [
                "market_factor_prices",
                "market_factor_features",
                "market_panel_training_dataset",
                "market_production_model_versions",
                "market_production_forecasts",
            ]:
                cur.execute(f"SELECT COUNT(*) AS count FROM {table}")
                stats[table] = int(cur.fetchone()["count"])
        conn.commit()
    return stats


def query_dataframe(sql: str, params: tuple = ()):
    import pandas as pd

    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
    return pd.DataFrame(rows)


def json_default(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return str(value)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, default=json_default), encoding="utf-8")


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def clean_float(value: Any) -> float | None:
    try:
        import math

        if value is None:
            return None
        value = float(value)
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    except (TypeError, ValueError):
        return None


def latest_quant_model_version() -> str:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT model_version
                FROM market_quant_forecasts
                GROUP BY model_version
                ORDER BY max(created_at) DESC, model_version DESC
                LIMIT 1
                """
            )
            row = cur.fetchone()
    return row["model_version"] if row else BASE_QUANT_MODEL_VERSION


def markdown_table(rows: list[dict], columns: list[str]) -> str:
    if not rows:
        return "_No rows._"
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join(["---"] * len(columns)) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(row.get(c, "")) for c in columns) + " |")
    return "\n".join(lines)

