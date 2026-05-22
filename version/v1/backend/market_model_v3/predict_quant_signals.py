from __future__ import annotations

import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3.common import HORIZONS, MODEL_DIR, MODEL_VERSION, connect, ensure_tables, log, query_dataframe, read_json, write_json
else:
    from .common import HORIZONS, MODEL_DIR, MODEL_VERSION, connect, ensure_tables, log, query_dataframe, read_json, write_json


def load_latest_features() -> pd.DataFrame:
    df = query_dataframe(
        """
            SELECT *
            FROM market_quant_features
            WHERE price_date = (SELECT max(price_date) FROM market_quant_features)
            ORDER BY metal_code
        """
    )
    if df.empty:
        raise RuntimeError("No latest market_quant_features rows available.")
    metal_map = {code: i for i, code in enumerate(sorted(df["metal_code"].unique()))}
    df["metal_id"] = df["metal_code"].map(metal_map).astype(int)
    return df


def confidence_score(predicted_return: float) -> float:
    value = abs(float(predicted_return))
    if value < 0.01:
        return 0.33
    if value <= 0.03:
        return 0.66
    return 0.9


def upsert_forecasts(rows: list[dict]) -> int:
    columns = [
        "model_version", "forecast_date", "metal_code", "metal_name", "base_price", "horizon_day",
        "predicted_return", "predicted_price", "predicted_direction", "direction_confidence",
        "relative_strength_score",
    ]
    sql = f"""
        INSERT INTO market_quant_forecasts ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (model_version, forecast_date, metal_code, horizon_day) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in columns if c not in {"model_version", "forecast_date", "metal_code", "horizon_day"}])},
        created_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, [tuple(row.get(c) for c in columns) for row in rows])
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    feature_columns = read_json(MODEL_DIR / "feature_columns.json")
    df = load_latest_features()
    for col in feature_columns:
        if col != "metal_id":
            df[col] = pd.to_numeric(df[col], errors="coerce")
    rows: list[dict] = []
    for horizon in HORIZONS:
        model_path = MODEL_DIR / f"model_return_{horizon}d.pkl"
        model = joblib.load(model_path)
        usable = df.dropna(subset=feature_columns).copy()
        predictions = model.predict(usable[feature_columns])
        for (_, row), predicted_return in zip(usable.iterrows(), predictions):
            predicted_return = float(predicted_return)
            base_price = float(row["close_price"])
            rows.append(
                {
                    "model_version": MODEL_VERSION,
                    "forecast_date": row["price_date"],
                    "metal_code": row["metal_code"],
                    "metal_name": row["metal_name"],
                    "base_price": base_price,
                    "horizon_day": horizon,
                    "predicted_return": predicted_return,
                    "predicted_price": base_price * (1 + predicted_return),
                    "predicted_direction": 1 if predicted_return > 0 else 0,
                    "direction_confidence": confidence_score(predicted_return),
                    "relative_strength_score": predicted_return,
                }
            )
    upserted = upsert_forecasts(rows)
    sample = rows[:10]
    report = {"upserted_rows": upserted, "forecast_date": str(df["price_date"].max()), "sample": sample}
    write_json(Path(__file__).resolve().parent / "prediction_report.json", report)
    log(f"forecasts upserted: {upserted}")
    return report


if __name__ == "__main__":
    main()
