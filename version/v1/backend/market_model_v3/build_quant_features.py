from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3.common import MIN_HISTORY_ROWS, connect, ensure_tables, log, query_dataframe, write_json
else:
    from .common import MIN_HISTORY_ROWS, connect, ensure_tables, log, query_dataframe, write_json


FEATURE_WINDOWS = [1, 3, 7, 14, 30, 60, 90]
ROLLING_WINDOWS = [7, 14, 30, 60, 90]


def _table_exists(cur, table: str) -> bool:
    cur.execute("SELECT to_regclass(%s) AS regclass", (table,))
    return cur.fetchone()["regclass"] is not None


def detect_source_table(cur) -> tuple[str, str]:
    if _table_exists(cur, "normalized_market_prices"):
        cur.execute("SELECT COUNT(*) AS count FROM normalized_market_prices WHERE price_date IS NOT NULL AND price IS NOT NULL")
        if cur.fetchone()["count"] >= MIN_HISTORY_ROWS:
            return (
                "normalized_market_prices",
                """
                SELECT metal_code, metal_name, price_date, price::float8 AS close_price,
                       source_code AS source_provider, source_type
                FROM normalized_market_prices
                WHERE price_date IS NOT NULL AND price IS NOT NULL AND is_available IS DISTINCT FROM false
                """,
            )
    if _table_exists(cur, "market_price_history"):
        return (
            "market_price_history",
            """
            SELECT metal_code, metal_name, price_date, price::float8 AS close_price,
                   source_provider, source_type
            FROM market_price_history
            WHERE price_date IS NOT NULL AND price IS NOT NULL
            """,
        )
    if _table_exists(cur, "market_price_series"):
        return (
            "market_price_series",
            """
            SELECT commodity_code AS metal_code, commodity_name AS metal_name,
                   price_date, price::float8 AS close_price, source AS source_provider,
                   price_kind AS source_type
            FROM market_price_series
            WHERE price_date IS NOT NULL AND price IS NOT NULL
            """,
        )
    raise RuntimeError("No supported market price source table found.")


def load_prices() -> tuple[str, pd.DataFrame]:
    with connect() as conn:
        with conn.cursor() as cur:
            source_table, sql = detect_source_table(cur)
    df = query_dataframe(sql)

    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    df["close_price"] = pd.to_numeric(df["close_price"], errors="coerce")
    df = df.dropna(subset=["metal_code", "price_date", "close_price"])
    df = df[df["close_price"] > 0].copy()
    df = (
        df.sort_values(["metal_code", "price_date", "source_provider", "source_type"])
        .groupby(["metal_code", "price_date"], as_index=False)
        .agg(
            metal_name=("metal_name", "last"),
            close_price=("close_price", "mean"),
            source_provider=("source_provider", "last"),
            source_type=("source_type", "last"),
        )
    )
    return source_table, df


def pct_rank_last(values: pd.Series) -> float:
    current = values.iloc[-1]
    if pd.isna(current):
        return np.nan
    return float((values <= current).mean())


def build_features(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    counts = df.groupby("metal_code").size().sort_values(ascending=False)
    selected = counts[counts >= MIN_HISTORY_ROWS].index.tolist()
    skipped = {code: f"valid_price_rows={int(count)} < {MIN_HISTORY_ROWS}" for code, count in counts.items() if count < MIN_HISTORY_ROWS}
    work = df[df["metal_code"].isin(selected)].sort_values(["metal_code", "price_date"]).copy()
    if work.empty:
        raise RuntimeError("No metal has enough history rows for market_model_v3.")

    parts = []
    for metal_code, g in work.groupby("metal_code", sort=False):
        g = g.sort_values("price_date").copy()
        for window in FEATURE_WINDOWS:
            g[f"return_{window}d"] = g["close_price"].pct_change(window)
        for window in ROLLING_WINDOWS:
            rolling = g["close_price"].rolling(window=window, min_periods=window)
            g[f"rolling_mean_{window}d"] = rolling.mean()
            g[f"rolling_std_{window}d"] = g[f"return_1d"].rolling(window=window, min_periods=window).std()
            g[f"_price_std_{window}d"] = rolling.std()
        for window in [7, 30, 90]:
            g[f"momentum_{window}d"] = g["close_price"] / g[f"rolling_mean_{window}d"] - 1
        g["zscore_30d"] = (g["close_price"] - g["rolling_mean_30d"]) / g["_price_std_30d"].replace(0, np.nan)
        g["zscore_90d"] = (g["close_price"] - g["rolling_mean_90d"]) / g["_price_std_90d"].replace(0, np.nan)
        g["drawdown_30d"] = g["close_price"] / g["close_price"].rolling(30, min_periods=30).max() - 1
        g["drawdown_90d"] = g["close_price"] / g["close_price"].rolling(90, min_periods=90).max() - 1
        g["pct_rank_30d"] = g["close_price"].rolling(30, min_periods=30).apply(pct_rank_last, raw=False)
        g["pct_rank_90d"] = g["close_price"].rolling(90, min_periods=90).apply(pct_rank_last, raw=False)
        for horizon in [7, 30, 90]:
            g[f"target_return_{horizon}d"] = g["close_price"].shift(-horizon) / g["close_price"] - 1
            g[f"target_direction_{horizon}d"] = np.where(g[f"target_return_{horizon}d"] > 0, 1, 0)
            g.loc[g[f"target_return_{horizon}d"].isna(), f"target_direction_{horizon}d"] = np.nan
        parts.append(g)

    features = pd.concat(parts, ignore_index=True)
    for horizon in [7, 30, 90]:
        daily_avg = features.groupby("price_date")[f"return_{horizon}d"].transform("mean")
        features[f"industrial_avg_return_{horizon}d"] = daily_avg
        features[f"relative_strength_{horizon}d"] = features[f"return_{horizon}d"] - daily_avg

    feature_cols = [
        c for c in features.columns
        if c not in {"metal_code", "metal_name", "price_date", "source_provider", "source_type"}
        and not c.startswith("_")
    ]
    coverage = {c: round(float(features[c].notna().mean()), 4) for c in feature_cols}
    samples = features.groupby("metal_code").size().astype(int).to_dict()
    report = {
        "selected_metals": selected,
        "skipped_metals": skipped,
        "sample_counts": samples,
        "date_range": [str(features["price_date"].min()), str(features["price_date"].max())],
        "coverage": coverage,
        "row_count": int(len(features)),
    }
    return features, report


def upsert_features(features: pd.DataFrame) -> int:
    columns = [
        "metal_code", "metal_name", "price_date", "close_price", "source_provider", "source_type",
        "return_1d", "return_3d", "return_7d", "return_14d", "return_30d", "return_60d", "return_90d",
        "rolling_mean_7d", "rolling_mean_14d", "rolling_mean_30d", "rolling_mean_60d", "rolling_mean_90d",
        "rolling_std_7d", "rolling_std_14d", "rolling_std_30d", "rolling_std_60d", "rolling_std_90d",
        "momentum_7d", "momentum_30d", "momentum_90d", "zscore_30d", "zscore_90d",
        "drawdown_30d", "drawdown_90d", "pct_rank_30d", "pct_rank_90d",
        "industrial_avg_return_7d", "industrial_avg_return_30d", "industrial_avg_return_90d",
        "relative_strength_7d", "relative_strength_30d", "relative_strength_90d",
        "target_return_7d", "target_return_30d", "target_return_90d",
        "target_direction_7d", "target_direction_30d", "target_direction_90d",
    ]
    clean = features[columns].replace({np.nan: None})
    update_cols = [c for c in columns if c not in {"metal_code", "price_date"}]
    sql = f"""
        INSERT INTO market_quant_features ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (metal_code, price_date) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in update_cols])},
        updated_at = now()
    """
    rows = [tuple(row) for row in clean.itertuples(index=False, name=None)]
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    source_table, prices = load_prices()
    log(f"source_table={source_table}, price_rows={len(prices)}")
    features, report = build_features(prices)
    report["source_table"] = source_table
    report["upserted_rows"] = upsert_features(features)
    write_json(Path(__file__).resolve().parent / "quant_feature_report.json", report)
    log(f"quant features upserted: {report['upserted_rows']}")
    log(f"selected metals: {', '.join(report['selected_metals'])}")
    return report


if __name__ == "__main__":
    main()
