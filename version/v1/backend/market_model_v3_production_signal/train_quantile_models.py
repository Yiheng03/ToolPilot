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
        MODEL_NAME,
        MODEL_VERSION,
        MODULE_DIR,
        PANEL_FEATURE_COLUMNS,
        connect,
        ensure_dirs,
        ensure_tables,
        log,
        query_dataframe,
        write_json,
    )
else:
    from .common import (
        HORIZONS,
        MODEL_DIR,
        MODEL_NAME,
        MODEL_VERSION,
        MODULE_DIR,
        PANEL_FEATURE_COLUMNS,
        connect,
        ensure_dirs,
        ensure_tables,
        log,
        query_dataframe,
        write_json,
    )

try:
    import lightgbm as lgb
except ImportError as exc:
    raise RuntimeError("LightGBM is required for production quantile models. Install lightgbm before running this script.") from exc


QUANTILES = {"p10": 0.10, "p50": 0.50, "p90": 0.90}
BASE_PARAMS = {
    "objective": "quantile",
    "n_estimators": 260,
    "learning_rate": 0.04,
    "num_leaves": 31,
    "min_child_samples": 12,
    "subsample": 0.9,
    "colsample_bytree": 0.9,
    "random_state": 20260522,
    "verbosity": -1,
}


def load_panel() -> pd.DataFrame:
    df = query_dataframe("SELECT * FROM market_panel_training_dataset ORDER BY price_date, metal_code")
    if df.empty:
        raise RuntimeError("market_panel_training_dataset is empty. Run build_production_panel_dataset.py first.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    df["metal_code"] = df["metal_code"].astype("category")
    for col in PANEL_FEATURE_COLUMNS:
        if col != "metal_code" and col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    for horizon in HORIZONS:
        df[f"target_return_{horizon}d"] = pd.to_numeric(df[f"target_return_{horizon}d"], errors="coerce")
    return df


def upsert_version(row: dict) -> None:
    columns = [
        "model_name",
        "model_version",
        "model_type",
        "horizon_day",
        "target_type",
        "train_start_date",
        "train_end_date",
        "feature_count",
        "sample_count",
        "metal_count",
        "factor_count",
        "model_path",
        "feature_config_path",
        "train_status",
    ]
    sql = f"""
        INSERT INTO market_production_model_versions ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (model_name, model_version, horizon_day, target_type) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"model_name", "model_version", "horizon_day", "target_type"}])},
        created_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(row.get(c) for c in columns))
        conn.commit()


def train_models() -> dict:
    ensure_tables()
    ensure_dirs()
    df = load_panel()
    feature_columns = PANEL_FEATURE_COLUMNS
    factor_count = int(query_dataframe("SELECT count(DISTINCT factor_code) AS count FROM market_factor_features").iloc[0]["count"])
    report = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "feature_columns": feature_columns,
        "quantiles": QUANTILES,
        "models": {},
    }
    quantile_config_path = MODEL_DIR / "quantile_feature_columns.json"
    write_json(quantile_config_path, feature_columns)

    for horizon in HORIZONS:
        target_col = f"target_return_{horizon}d"
        train_df = df.dropna(subset=[target_col]).copy()
        if train_df.empty:
            continue
        for label, alpha in QUANTILES.items():
            params = {**BASE_PARAMS, "alpha": alpha}
            model = lgb.LGBMRegressor(**params)
            model.fit(train_df[feature_columns], train_df[target_col], categorical_feature=["metal_code"])
            model_path = MODEL_DIR / f"quantile_return_{horizon}d_{label}.pkl"
            joblib.dump(model, model_path)
            pred = model.predict(train_df[feature_columns])
            mae = float(np.mean(np.abs(pred - train_df[target_col].to_numpy())))
            row = {
                "model_name": MODEL_NAME,
                "model_version": MODEL_VERSION,
                "model_type": "lightgbm_quantile_return",
                "horizon_day": horizon,
                "target_type": f"return_{label}",
                "train_start_date": train_df["price_date"].min(),
                "train_end_date": train_df["price_date"].max(),
                "feature_count": len(feature_columns),
                "sample_count": len(train_df),
                "metal_count": int(train_df["metal_code"].nunique()),
                "factor_count": factor_count,
                "model_path": str(model_path),
                "feature_config_path": str(quantile_config_path),
                "train_status": "success",
                "train_mae_return": mae,
            }
            upsert_version(row)
            report["models"][f"{horizon}_{label}"] = row
            log(f"quantile horizon={horizon} {label} samples={len(train_df)} mae={mae:.6f}")
    write_json(MODULE_DIR / "quantile_train_report.json", report)
    return report


def main() -> dict:
    return train_models()


if __name__ == "__main__":
    main()

