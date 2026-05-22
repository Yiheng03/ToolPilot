from __future__ import annotations

import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3.common import HORIZONS, MODEL_DIR, MODEL_NAME, MODEL_VERSION, connect, ensure_dirs, ensure_tables, log, query_dataframe, write_json
else:
    from .common import HORIZONS, MODEL_DIR, MODEL_NAME, MODEL_VERSION, connect, ensure_dirs, ensure_tables, log, query_dataframe, write_json

try:
    import lightgbm as lgb
except ImportError as exc:
    raise RuntimeError("LightGBM is required for market_model_v3. Install lightgbm before training.") from exc


BASE_FEATURE_COLUMNS = [
    "close_price",
    "return_1d", "return_3d", "return_7d", "return_14d", "return_30d", "return_60d", "return_90d",
    "rolling_mean_7d", "rolling_mean_14d", "rolling_mean_30d", "rolling_mean_60d", "rolling_mean_90d",
    "rolling_std_7d", "rolling_std_14d", "rolling_std_30d", "rolling_std_60d", "rolling_std_90d",
    "momentum_7d", "momentum_30d", "momentum_90d", "zscore_30d", "zscore_90d",
    "drawdown_30d", "drawdown_90d", "pct_rank_30d", "pct_rank_90d",
    "industrial_avg_return_7d", "industrial_avg_return_30d", "industrial_avg_return_90d",
    "relative_strength_7d", "relative_strength_30d", "relative_strength_90d",
    "metal_id",
]

MODEL_PARAMS = {
    "objective": "regression",
    "n_estimators": 260,
    "learning_rate": 0.04,
    "num_leaves": 31,
    "max_depth": -1,
    "min_child_samples": 12,
    "subsample": 0.9,
    "colsample_bytree": 0.9,
    "reg_alpha": 0.02,
    "reg_lambda": 0.3,
    "random_state": 20260522,
    "verbosity": -1,
}


def load_training_frame() -> pd.DataFrame:
    sql = "SELECT * FROM market_quant_features ORDER BY price_date, metal_code"
    df = query_dataframe(sql)
    if df.empty:
        raise RuntimeError("market_quant_features is empty. Run build_quant_features.py first.")
    df["price_date"] = pd.to_datetime(df["price_date"]).dt.date
    metal_map = {code: i for i, code in enumerate(sorted(df["metal_code"].unique()))}
    df["metal_id"] = df["metal_code"].map(metal_map).astype(int)
    for col in BASE_FEATURE_COLUMNS:
        if col != "metal_id":
            df[col] = pd.to_numeric(df[col], errors="coerce")
    for horizon in HORIZONS:
        df[f"target_return_{horizon}d"] = pd.to_numeric(df[f"target_return_{horizon}d"], errors="coerce")
    return df


def rank_ic_by_date(frame: pd.DataFrame, pred: np.ndarray, target_col: str) -> tuple[float | None, float | None, float | None]:
    temp = frame[["price_date", target_col]].copy()
    temp["pred"] = pred
    values = []
    for _, g in temp.groupby("price_date"):
        if len(g) < 2 or g[target_col].nunique(dropna=True) < 2 or g["pred"].nunique(dropna=True) < 2:
            continue
        ic = g["pred"].rank().corr(g[target_col].rank())
        if pd.notna(ic):
            values.append(float(ic))
    if not values:
        return None, None, None
    mean = float(np.mean(values))
    std = float(np.std(values, ddof=1)) if len(values) > 1 else 0.0
    sharpe = mean / std if std else None
    return mean, std, sharpe


def upsert_model_version(row: dict) -> None:
    columns = [
        "model_name", "model_version", "model_type", "horizon_day", "train_start_date", "train_end_date",
        "feature_count", "sample_count", "metal_count", "model_path", "feature_config_path", "train_status",
        "mae_return", "direction_accuracy", "rank_ic_mean", "rank_ic_std", "rank_ic_sharpe",
    ]
    sql = f"""
        INSERT INTO market_model_versions ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (model_name, model_version, horizon_day) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"model_name", "model_version", "horizon_day"}])},
        created_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(row.get(c) for c in columns))
        conn.commit()


def train_models() -> dict:
    ensure_tables()
    ensure_dirs()
    df = load_training_frame()
    selected_metals = sorted(df["metal_code"].unique().tolist())
    feature_columns = BASE_FEATURE_COLUMNS
    write_json(MODEL_DIR / "feature_columns.json", feature_columns)

    report = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "selected_metals": selected_metals,
        "feature_columns": feature_columns,
        "horizon_days": HORIZONS,
        "model_params": MODEL_PARAMS,
        "horizons": {},
    }

    for horizon in HORIZONS:
        target_col = f"target_return_{horizon}d"
        train_df = df.dropna(subset=feature_columns + [target_col]).sort_values(["price_date", "metal_code"]).copy()
        if train_df.empty:
            status = "skipped_no_complete_samples"
            log(f"horizon={horizon} skipped: no complete samples")
            continue
        model = lgb.LGBMRegressor(**MODEL_PARAMS)
        model.fit(train_df[feature_columns], train_df[target_col])
        pred = model.predict(train_df[feature_columns])
        mae = float(np.mean(np.abs(pred - train_df[target_col].to_numpy())))
        direction_accuracy = float((np.sign(pred) == np.sign(train_df[target_col].to_numpy())).mean())
        rank_ic_mean, rank_ic_std, rank_ic_sharpe = rank_ic_by_date(train_df, pred, target_col)
        model_path = MODEL_DIR / f"model_return_{horizon}d.pkl"
        joblib.dump(model, model_path)
        version_row = {
            "model_name": MODEL_NAME,
            "model_version": MODEL_VERSION,
            "model_type": "lightgbm_regressor_direct_return",
            "horizon_day": horizon,
            "train_start_date": train_df["price_date"].min(),
            "train_end_date": train_df["price_date"].max(),
            "feature_count": len(feature_columns),
            "sample_count": len(train_df),
            "metal_count": train_df["metal_code"].nunique(),
            "model_path": str(model_path),
            "feature_config_path": str(MODEL_DIR / "feature_columns.json"),
            "train_status": "success",
            "mae_return": mae,
            "direction_accuracy": direction_accuracy,
            "rank_ic_mean": rank_ic_mean,
            "rank_ic_std": rank_ic_std,
            "rank_ic_sharpe": rank_ic_sharpe,
        }
        upsert_model_version(version_row)
        report["horizons"][str(horizon)] = version_row
        log(f"horizon={horizon} success samples={len(train_df)} mae_return={mae:.6f}")

    config = {
        "model_name": MODEL_NAME,
        "model_version": MODEL_VERSION,
        "train_start_date": str(df["price_date"].min()),
        "train_end_date": str(df["price_date"].max()),
        "selected_metals": selected_metals,
        "feature_columns": feature_columns,
        "horizon_days": HORIZONS,
        "model_params": MODEL_PARAMS,
    }
    write_json(MODEL_DIR / "model_config.json", config)
    write_json(Path(__file__).resolve().parent / "train_report.json", report)
    return report


def main() -> dict:
    return train_models()


if __name__ == "__main__":
    main()
