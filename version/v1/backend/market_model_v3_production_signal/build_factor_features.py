from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import MODULE_DIR, connect, ensure_tables, log, query_dataframe, write_json
else:
    from .common import MODULE_DIR, connect, ensure_tables, log, query_dataframe, write_json


def load_factor_prices() -> pd.DataFrame:
    df = query_dataframe(
        """
        SELECT factor_code, factor_name, factor_type, price_date, avg(close_price::float8) AS close_price
        FROM market_factor_prices
        GROUP BY factor_code, factor_name, factor_type, price_date
        ORDER BY factor_code, price_date
        """
    )
    if df.empty:
        raise RuntimeError("market_factor_prices is empty. Run collect_factor_prices.py first.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    df["close_price"] = pd.to_numeric(df["close_price"], errors="coerce")
    return df.dropna(subset=["factor_code", "price_date", "close_price"])


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    frames = []
    for _, g in df.sort_values(["factor_code", "price_date"]).groupby("factor_code", sort=False):
        g = g.sort_values("price_date").copy()
        for horizon in [1, 7, 30, 90]:
            g[f"return_{horizon}d"] = g["close_price"].pct_change(horizon)
        g["rolling_std_30d"] = g["return_1d"].rolling(30, min_periods=30).std()
        g["rolling_std_90d"] = g["return_1d"].rolling(90, min_periods=90).std()
        mean_30 = g["close_price"].rolling(30, min_periods=30).mean()
        mean_90 = g["close_price"].rolling(90, min_periods=90).mean()
        std_90 = g["close_price"].rolling(90, min_periods=90).std()
        g["momentum_30d"] = g["close_price"] / mean_30 - 1
        g["momentum_90d"] = g["close_price"] / mean_90 - 1
        g["zscore_90d"] = (g["close_price"] - mean_90) / std_90.replace(0, np.nan)
        frames.append(g)
    return pd.concat(frames, ignore_index=True)


def upsert_features(df: pd.DataFrame) -> int:
    columns = [
        "factor_code",
        "factor_name",
        "factor_type",
        "price_date",
        "close_price",
        "return_1d",
        "return_7d",
        "return_30d",
        "return_90d",
        "rolling_std_30d",
        "rolling_std_90d",
        "momentum_30d",
        "momentum_90d",
        "zscore_90d",
    ]
    clean = df[columns].replace({np.nan: None})
    rows = [tuple(row) for row in clean.itertuples(index=False, name=None)]
    sql = f"""
        INSERT INTO market_factor_features ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (factor_code, price_date) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"factor_code", "price_date"}])},
        updated_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    prices = load_factor_prices()
    features = build_features(prices)
    upserted = upsert_features(features)
    report = {
        "input_rows": int(len(prices)),
        "upserted_rows": upserted,
        "factor_count": int(features["factor_code"].nunique()),
        "date_range": [str(features["price_date"].min()), str(features["price_date"].max())],
        "no_future_leakage": "all returns, rolling statistics, momentum, and zscore use current or prior rows within each factor_code",
    }
    write_json(MODULE_DIR / "factor_feature_report.json", report)
    log(f"factor features upserted: {upserted}")
    return report


if __name__ == "__main__":
    main()

