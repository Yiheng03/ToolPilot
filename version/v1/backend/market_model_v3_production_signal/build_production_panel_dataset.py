from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import (
        HORIZONS,
        MODULE_DIR,
        connect,
        ensure_tables,
        latest_quant_model_version,
        log,
        query_dataframe,
        write_json,
    )
else:
    from .common import HORIZONS, MODULE_DIR, connect, ensure_tables, latest_quant_model_version, log, query_dataframe, write_json


RATIO_COLUMNS = {
    "cu_al_ratio": ("CU", "AL"),
    "ni_co_ratio": ("NI", "CO"),
    "co_cu_ratio": ("CO", "CU"),
    "ni_cu_ratio": ("NI", "CU"),
    "sn_cu_ratio": ("SN", "CU"),
    "zn_al_ratio": ("ZN", "AL"),
    "pb_al_ratio": ("PB", "AL"),
    "iron_ore_cu_ratio": ("IRON_ORE", "CU"),
}


def load_quant_features() -> pd.DataFrame:
    df = query_dataframe(
        """
        SELECT metal_code, metal_name, price_date, close_price::float8 AS close_price,
               return_1d, return_7d, return_30d, return_90d,
               rolling_std_30d, rolling_std_90d,
               momentum_30d, momentum_90d, zscore_90d, drawdown_90d,
               target_return_7d, target_return_30d, target_return_90d
        FROM market_quant_features
        ORDER BY price_date, metal_code
        """
    )
    if df.empty:
        raise RuntimeError("market_quant_features is empty.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    return df


def load_lgb_forecasts(model_version: str) -> pd.DataFrame:
    df = query_dataframe(
        """
        SELECT forecast_date AS price_date, metal_code, horizon_day, predicted_return
        FROM market_quant_forecasts
        WHERE model_version = %s
        """,
        (model_version,),
    )
    if df.empty:
        log(f"no market_quant_forecasts rows for model_version={model_version}; panel LGB features will be null")
        return pd.DataFrame(columns=["price_date", "metal_code"] + [f"pred_lgb_return_{h}d" for h in HORIZONS])
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    pivot = df.pivot_table(index=["price_date", "metal_code"], columns="horizon_day", values="predicted_return", aggfunc="last").reset_index()
    pivot.columns = [f"pred_lgb_return_{c}d" if isinstance(c, int) else c for c in pivot.columns]
    for horizon in HORIZONS:
        col = f"pred_lgb_return_{horizon}d"
        if col not in pivot.columns:
            pivot[col] = np.nan
    return pivot


def load_factor_aggregates() -> pd.DataFrame:
    factors = query_dataframe(
        """
        SELECT price_date, factor_code, factor_type, return_30d, return_90d
        FROM market_factor_features
        ORDER BY price_date, factor_code
        """
    )
    if factors.empty:
        return pd.DataFrame(columns=["price_date"])
    factors["price_date"] = pd.to_datetime(factors["price_date"]).dt.date
    specs = {
        "industrial_metals": lambda f: f["factor_type"].eq("industrial_metal"),
        "energy": lambda f: f["factor_type"].eq("energy"),
        "usd": lambda f: f["factor_code"].isin(["DXY", "USD_CNY"]),
        "precious_metals": lambda f: f["factor_type"].eq("precious_metal"),
        "risk_asset": lambda f: f["factor_type"].eq("equity_index"),
    }
    parts = []
    for prefix, mask_fn in specs.items():
        sub = factors[mask_fn(factors)].copy()
        if sub.empty:
            continue
        agg = sub.groupby("price_date", as_index=False).agg(
            **{
                f"{prefix}_return_30d": ("return_30d", "mean"),
                f"{prefix}_return_90d": ("return_90d", "mean"),
            }
        )
        parts.append(agg)
    if not parts:
        return pd.DataFrame(columns=["price_date"])
    out = parts[0]
    for part in parts[1:]:
        out = out.merge(part, on="price_date", how="outer")
    return out


def load_pair_ratios_from_quant_prices(quant: pd.DataFrame) -> pd.DataFrame:
    price = quant.pivot_table(index="price_date", columns="metal_code", values="close_price", aggfunc="last").reset_index()
    for col, (base, compare) in RATIO_COLUMNS.items():
        if base in price.columns and compare in price.columns:
            price[col] = price[base] / price[compare].replace(0, np.nan)
        else:
            price[col] = np.nan
    return price[["price_date"] + list(RATIO_COLUMNS)]


def overlay_pair_ratios_from_pair_table(ratios: pd.DataFrame) -> pd.DataFrame:
    pair_df = query_dataframe(
        """
        SELECT price_date, base_metal_code, compare_metal_code, price_ratio
        FROM market_pair_features
        """
    )
    if pair_df.empty:
        return ratios
    pair_df["price_date"] = pd.to_datetime(pair_df["price_date"]).dt.date
    out = ratios.copy()
    for col, (base, compare) in RATIO_COLUMNS.items():
        sub = pair_df[(pair_df["base_metal_code"] == base) & (pair_df["compare_metal_code"] == compare)]
        if sub.empty:
            continue
        mapped = sub.set_index("price_date")["price_ratio"].to_dict()
        out[col] = out["price_date"].map(mapped).combine_first(out[col])
    return out


def build_panel() -> tuple[pd.DataFrame, dict]:
    quant_model_version = latest_quant_model_version()
    quant = load_quant_features()
    lgb = load_lgb_forecasts(quant_model_version)
    factors = load_factor_aggregates()
    pair_ratios = overlay_pair_ratios_from_pair_table(load_pair_ratios_from_quant_prices(quant))

    rename = {
        "return_1d": "metal_return_1d",
        "return_7d": "metal_return_7d",
        "return_30d": "metal_return_30d",
        "return_90d": "metal_return_90d",
        "rolling_std_30d": "metal_volatility_30d",
        "rolling_std_90d": "metal_volatility_90d",
        "momentum_30d": "metal_momentum_30d",
        "momentum_90d": "metal_momentum_90d",
        "zscore_90d": "metal_zscore_90d",
        "drawdown_90d": "metal_drawdown_90d",
    }
    panel = quant.rename(columns=rename)
    panel = panel.merge(lgb, on=["price_date", "metal_code"], how="left")
    panel = panel.merge(factors, on="price_date", how="left")
    panel = panel.merge(pair_ratios, on="price_date", how="left")

    for horizon in HORIZONS:
        target = f"target_return_{horizon}d"
        excess = f"target_excess_return_{horizon}d"
        daily_mean = panel.groupby("price_date")[target].transform("mean")
        panel[excess] = panel[target] - daily_mean

    report = {
        "base_quant_model_version": quant_model_version,
        "row_count": int(len(panel)),
        "metal_count": int(panel["metal_code"].nunique()),
        "date_range": [str(panel["price_date"].min()), str(panel["price_date"].max())],
        "factor_columns": [c for c in panel.columns if c.endswith("_return_30d") or c.endswith("_return_90d")],
        "pair_ratio_columns": list(RATIO_COLUMNS),
        "no_future_leakage": "feature columns are joined by price_date from same-day or earlier rolling features; targets are stored separately and excluded from model feature_columns",
    }
    return panel, report


def upsert_panel(panel: pd.DataFrame) -> int:
    columns = [
        "price_date",
        "metal_code",
        "metal_name",
        "close_price",
        "pred_lgb_return_7d",
        "pred_lgb_return_30d",
        "pred_lgb_return_90d",
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
        "target_return_7d",
        "target_return_30d",
        "target_return_90d",
        "target_excess_return_7d",
        "target_excess_return_30d",
        "target_excess_return_90d",
    ]
    for col in columns:
        if col not in panel.columns:
            panel[col] = np.nan
    clean = panel[columns].replace({np.nan: None})
    rows = [tuple(row) for row in clean.itertuples(index=False, name=None)]
    sql = f"""
        INSERT INTO market_panel_training_dataset ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (price_date, metal_code) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"price_date", "metal_code"}])},
        updated_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    panel, report = build_panel()
    report["upserted_rows"] = upsert_panel(panel)
    report["complete_target_rows"] = {
        str(h): int(panel[f"target_excess_return_{h}d"].notna().sum()) for h in HORIZONS
    }
    write_json(MODULE_DIR / "production_panel_dataset_report.json", report)
    log(f"panel dataset upserted: {report['upserted_rows']} rows")
    return report


if __name__ == "__main__":
    main()

