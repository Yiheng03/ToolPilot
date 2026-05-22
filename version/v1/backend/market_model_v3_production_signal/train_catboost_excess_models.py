from __future__ import annotations

import sys
from pathlib import Path

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
    from catboost import CatBoostRegressor, Pool
except ImportError as exc:
    raise RuntimeError("CatBoostRegressor is required for production excess-return models. Install catboost before running this script.") from exc


CATBOOST_PARAMS = {
    "loss_function": "RMSE",
    "iterations": 500,
    "learning_rate": 0.04,
    "depth": 6,
    "l2_leaf_reg": 5,
    "random_seed": 20260522,
    "allow_writing_files": False,
    "verbose": False,
}


def load_panel() -> pd.DataFrame:
    df = query_dataframe("SELECT * FROM market_panel_training_dataset ORDER BY price_date, metal_code")
    if df.empty:
        raise RuntimeError("market_panel_training_dataset is empty. Run build_production_panel_dataset.py first.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    df["metal_code"] = df["metal_code"].astype(str)
    for col in PANEL_FEATURE_COLUMNS:
        if col != "metal_code" and col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    for horizon in HORIZONS:
        df[f"target_excess_return_{horizon}d"] = pd.to_numeric(df[f"target_excess_return_{horizon}d"], errors="coerce")
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
    write_json(MODEL_DIR / "feature_columns.json", feature_columns)
    config = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "model_type": "catboost_excess_return_panel",
        "feature_columns": feature_columns,
        "categorical_features": ["metal_code"],
        "target_columns": {str(h): f"target_excess_return_{h}d" for h in HORIZONS},
        "params": CATBOOST_PARAMS,
        "target_policy": "target columns are excluded from feature_columns to avoid future data leakage",
    }
    write_json(MODEL_DIR / "model_config.json", config)
    report = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "feature_columns": feature_columns,
        "horizons": {},
    }
    factor_count = int(query_dataframe("SELECT count(DISTINCT factor_code) AS count FROM market_factor_features").iloc[0]["count"])

    for horizon in HORIZONS:
        target_col = f"target_excess_return_{horizon}d"
        train_df = df.dropna(subset=[target_col]).copy()
        if train_df.empty:
            status = "skipped_no_target_samples"
            row = {
                "model_name": MODEL_NAME,
                "model_version": MODEL_VERSION,
                "model_type": "catboost_excess_return_panel",
                "horizon_day": horizon,
                "target_type": "excess_return",
                "feature_count": len(feature_columns),
                "sample_count": 0,
                "metal_count": 0,
                "factor_count": factor_count,
                "model_path": str(MODEL_DIR / f"catboost_excess_return_{horizon}d.cbm"),
                "feature_config_path": str(MODEL_DIR / "feature_columns.json"),
                "train_status": status,
            }
            upsert_version(row)
            report["horizons"][str(horizon)] = row
            continue
        pool = Pool(train_df[feature_columns], train_df[target_col], cat_features=["metal_code"])
        model = CatBoostRegressor(**CATBOOST_PARAMS)
        model.fit(pool)
        model_path = MODEL_DIR / f"catboost_excess_return_{horizon}d.cbm"
        model.save_model(model_path)
        pred = model.predict(pool)
        mae = float(np.mean(np.abs(pred - train_df[target_col].to_numpy())))
        row = {
            "model_name": MODEL_NAME,
            "model_version": MODEL_VERSION,
            "model_type": "catboost_excess_return_panel",
            "horizon_day": horizon,
            "target_type": "excess_return",
            "train_start_date": train_df["price_date"].min(),
            "train_end_date": train_df["price_date"].max(),
            "feature_count": len(feature_columns),
            "sample_count": len(train_df),
            "metal_count": int(train_df["metal_code"].nunique()),
            "factor_count": factor_count,
            "model_path": str(model_path),
            "feature_config_path": str(MODEL_DIR / "feature_columns.json"),
            "train_status": "success",
            "train_mae_excess_return": mae,
        }
        upsert_version(row)
        report["horizons"][str(horizon)] = row
        log(f"catboost excess horizon={horizon} samples={len(train_df)} mae={mae:.6f}")
    write_json(MODULE_DIR / "catboost_excess_train_report.json", report)
    return report


def main() -> dict:
    return train_models()


if __name__ == "__main__":
    main()

