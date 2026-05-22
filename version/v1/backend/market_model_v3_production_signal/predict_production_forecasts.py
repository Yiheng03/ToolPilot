from __future__ import annotations

import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import (
        HORIZONS,
        MODEL_DIR,
        MODEL_VERSION,
        MODULE_DIR,
        PANEL_FEATURE_COLUMNS,
        connect,
        ensure_tables,
        log,
        query_dataframe,
        read_json,
        write_json,
    )
else:
    from .common import HORIZONS, MODEL_DIR, MODEL_VERSION, MODULE_DIR, PANEL_FEATURE_COLUMNS, connect, ensure_tables, log, query_dataframe, read_json, write_json

try:
    from catboost import CatBoostRegressor, Pool
except ImportError as exc:
    raise RuntimeError("CatBoostRegressor is required to generate production forecasts. Install catboost before running this script.") from exc


def load_latest_panel() -> pd.DataFrame:
    df = query_dataframe(
        """
        SELECT *
        FROM market_panel_training_dataset
        WHERE price_date = (SELECT max(price_date) FROM market_panel_training_dataset)
        ORDER BY metal_code
        """
    )
    if df.empty:
        raise RuntimeError("No latest market_panel_training_dataset rows available.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    df["metal_code"] = df["metal_code"].astype(str)
    for col in PANEL_FEATURE_COLUMNS:
        if col != "metal_code" and col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def market_factor_return(row: pd.Series, horizon: int) -> float:
    if horizon == 90:
        value = row.get("industrial_metals_return_90d")
    else:
        value = row.get("industrial_metals_return_30d")
    return 0.0 if pd.isna(value) else float(value)


def pair_adjustments(df: pd.DataFrame) -> pd.Series:
    ratio_cols = [
        "cu_al_ratio",
        "ni_co_ratio",
        "co_cu_ratio",
        "ni_cu_ratio",
        "sn_cu_ratio",
        "zn_al_ratio",
        "pb_al_ratio",
        "iron_ore_cu_ratio",
    ]
    values = {}
    for col in ratio_cols:
        if col not in df.columns or df[col].dropna().empty:
            values[col] = 0.0
            continue
        latest = float(df[col].dropna().iloc[0])
        values[col] = latest
    raw_by_metal: dict[str, float] = {}
    for metal in df["metal_code"].unique():
        raw = 0.0
        if metal == "CU":
            raw += values["cu_al_ratio"] + values["co_cu_ratio"] * -0.5 + values["ni_cu_ratio"] * -0.5
        elif metal == "AL":
            raw += -values["cu_al_ratio"] - values["zn_al_ratio"] * 0.5 - values["pb_al_ratio"] * 0.5
        elif metal == "NI":
            raw += values["ni_co_ratio"] + values["ni_cu_ratio"]
        elif metal == "CO":
            raw += -values["ni_co_ratio"] + values["co_cu_ratio"]
        elif metal == "SN":
            raw += values["sn_cu_ratio"]
        elif metal == "ZN":
            raw += values["zn_al_ratio"]
        elif metal == "PB":
            raw += values["pb_al_ratio"]
        elif metal == "IRON_ORE":
            raw += values["iron_ore_cu_ratio"]
        raw_by_metal[metal] = raw
    arr = np.array(list(raw_by_metal.values()), dtype=float)
    if len(arr) > 1 and np.nanstd(arr) > 0:
        normalized = {m: (v - float(np.nanmean(arr))) / float(np.nanstd(arr)) for m, v in raw_by_metal.items()}
    else:
        normalized = {m: 0.0 for m in raw_by_metal}
    return df["metal_code"].map(lambda m: float(np.clip(normalized.get(m, 0.0) * 0.005, -0.02, 0.02)))


def signal_strength(value: float) -> float:
    return float(min(1.0, max(0.0, abs(value) / 0.08)))


def direction(value: float) -> str:
    if value > 0.002:
        return "上涨"
    if value < -0.002:
        return "下跌"
    return "震荡"


def data_quality(row: pd.Series, feature_columns: list[str]) -> float:
    usable = [c for c in feature_columns if c != "metal_code"]
    present = sum(pd.notna(row.get(c)) for c in usable)
    return round(float(present / max(1, len(usable))), 4)


def downgrade(level: str) -> str:
    levels = ["低", "中", "高"]
    return levels[max(0, levels.index(level) - 1)]


def load_interval_width_p75() -> dict[int, float]:
    df = query_dataframe(
        """
        SELECT horizon_day,
               percentile_cont(0.75) WITHIN GROUP (
                 ORDER BY predicted_return_p90 - predicted_return_p10
               ) AS width_p75
        FROM market_production_forecasts
        WHERE predicted_return_p10 IS NOT NULL
          AND predicted_return_p90 IS NOT NULL
          AND predicted_return_p90 >= predicted_return_p10
        GROUP BY horizon_day
        """
    )
    if df.empty:
        return {}
    return {int(row["horizon_day"]): float(row["width_p75"]) for _, row in df.iterrows() if pd.notna(row["width_p75"])}


def missing_critical_factor_count() -> tuple[int, int, list[str]]:
    critical = ["WTI", "GOLD", "DXY", "USD_CNY"]
    df = query_dataframe("SELECT DISTINCT factor_code FROM market_factor_prices")
    present = set(df["factor_code"].tolist()) if not df.empty else set()
    missing = [code for code in critical if code not in present]
    return len(missing), len(critical), missing


def reliability(
    quality: float,
    p10: float | None,
    p50: float | None,
    p90: float | None,
    width_p75: float | None,
    missing_critical_count: int,
    critical_total: int,
) -> str:
    if p10 is None or p50 is None or p90 is None:
        return "低"
    if p10 > 0 and p50 > 0 and p90 > 0:
        level = "高"
    elif p10 < 0 and p50 < 0 and p90 < 0:
        level = "高"
    elif p10 < 0 < p90:
        level = "中"
    else:
        level = "中"
    width = p90 - p10
    if width_p75 is not None and width > width_p75:
        level = downgrade(level)
    if critical_total and missing_critical_count / critical_total > 0.5:
        level = downgrade(level)
    if quality < 0.7:
        level = downgrade(level)
    return level


def upsert_forecasts(rows: list[dict]) -> int:
    columns = [
        "model_version",
        "forecast_date",
        "metal_code",
        "metal_name",
        "base_price",
        "horizon_day",
        "pred_lgb_return",
        "pred_catboost_excess_return",
        "pred_market_factor_return",
        "pred_pair_adjustment",
        "final_predicted_return",
        "final_predicted_price",
        "predicted_direction",
        "predicted_return_p10",
        "predicted_return_p50",
        "predicted_return_p90",
        "predicted_price_p10",
        "predicted_price_p50",
        "predicted_price_p90",
        "signal_strength",
        "relative_strength_rank",
        "volatility_level",
        "key_drivers",
        "data_quality_score",
        "model_reliability_level",
    ]
    sql = f"""
        INSERT INTO market_production_forecasts ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (model_version, forecast_date, metal_code, horizon_day) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"model_version", "forecast_date", "metal_code", "horizon_day"}])}
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, [tuple(row.get(c) for c in columns) for row in rows])
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    feature_columns = read_json(MODEL_DIR / "feature_columns.json")
    df = load_latest_panel()
    pair_adj = pair_adjustments(df)
    width_p75_by_horizon = load_interval_width_p75()
    missing_critical_count, critical_total, missing_critical_factors = missing_critical_factor_count()
    rows: list[dict] = []
    forecast_date = df["price_date"].max()

    for horizon in HORIZONS:
        cat_model = CatBoostRegressor()
        cat_model.load_model(MODEL_DIR / f"catboost_excess_return_{horizon}d.cbm")
        cat_pred = cat_model.predict(Pool(df[feature_columns], cat_features=["metal_code"]))
        q_preds: dict[str, np.ndarray] = {}
        q_df = df.copy()
        q_df["metal_code"] = q_df["metal_code"].astype("category")
        for label in ["p10", "p50", "p90"]:
            q_model = joblib.load(MODEL_DIR / f"quantile_return_{horizon}d_{label}.pkl")
            q_preds[label] = q_model.predict(q_df[feature_columns])

        horizon_rows = []
        for i, (_, row) in enumerate(df.iterrows()):
            base_price = float(row["close_price"])
            pred_lgb = row.get(f"pred_lgb_return_{horizon}d")
            pred_lgb = 0.0 if pd.isna(pred_lgb) else float(pred_lgb)
            pred_cat = float(cat_pred[i])
            pred_factor = market_factor_return(row, horizon)
            pred_pair = float(pair_adj.iloc[i])
            final_return = 0.45 * pred_lgb + 0.35 * (pred_cat + pred_factor) + 0.20 * pred_pair
            p10 = float(q_preds["p10"][i])
            p50 = float(q_preds["p50"][i])
            p90 = float(q_preds["p90"][i])
            ordered = sorted([p10, p50, p90])
            p10, p50, p90 = ordered[0], ordered[1], ordered[2]
            quality = data_quality(row, feature_columns)
            vol = row.get("metal_volatility_30d")
            if pd.isna(vol):
                volatility_level = "未知"
            elif float(vol) >= 0.03:
                volatility_level = "高"
            elif float(vol) >= 0.015:
                volatility_level = "中"
            else:
                volatility_level = "低"
            key_drivers = {
                "base_lgb": pred_lgb,
                "catboost_excess": pred_cat,
                "market_factor": pred_factor,
                "pair_adjustment": pred_pair,
            }
            horizon_rows.append(
                {
                    "model_version": MODEL_VERSION,
                    "forecast_date": forecast_date,
                    "metal_code": row["metal_code"],
                    "metal_name": row["metal_name"],
                    "base_price": base_price,
                    "horizon_day": horizon,
                    "pred_lgb_return": pred_lgb,
                    "pred_catboost_excess_return": pred_cat,
                    "pred_market_factor_return": pred_factor,
                    "pred_pair_adjustment": pred_pair,
                    "final_predicted_return": final_return,
                    "final_predicted_price": base_price * (1 + final_return),
                    "predicted_direction": direction(final_return),
                    "predicted_return_p10": p10,
                    "predicted_return_p50": p50,
                    "predicted_return_p90": p90,
                    "predicted_price_p10": base_price * (1 + p10),
                    "predicted_price_p50": base_price * (1 + p50),
                    "predicted_price_p90": base_price * (1 + p90),
                    "signal_strength": signal_strength(final_return),
                    "volatility_level": volatility_level,
                    "key_drivers": key_drivers,
                    "data_quality_score": quality,
                    "model_reliability_level": reliability(
                        quality,
                        p10,
                        p50,
                        p90,
                        width_p75_by_horizon.get(horizon),
                        missing_critical_count,
                        critical_total,
                    ),
                }
            )
        rank_frame = pd.DataFrame(horizon_rows)
        rank_frame["relative_strength_rank"] = rank_frame["final_predicted_return"].rank(ascending=False, method="first").astype(int)
        rows.extend(rank_frame.to_dict(orient="records"))

    for row in rows:
        row["key_drivers"] = __import__("json").dumps(row["key_drivers"], ensure_ascii=False)
    upserted = upsert_forecasts(rows)
    report = {
        "upserted_rows": upserted,
        "forecast_date": str(forecast_date),
        "sample": rows[:10],
        "formula": "0.45*lgb + 0.35*(catboost_excess + market_factor) + 0.20*pair_adjustment",
        "reliability_rule": "one-sided quantile intervals start high; intervals crossing zero are capped at medium; wide intervals, missing critical external factors >50%, and data_quality_score <0.7 each downgrade one level",
        "missing_critical_factors": missing_critical_factors,
    }
    write_json(MODULE_DIR / "production_prediction_report.json", report)
    log(f"production forecasts upserted: {upserted}")
    return report


if __name__ == "__main__":
    main()
