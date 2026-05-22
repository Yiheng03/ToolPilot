from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3.common import MODEL_VERSION, connect, ensure_tables, log, query_dataframe, write_json
else:
    from .common import MODEL_VERSION, connect, ensure_tables, log, query_dataframe, write_json


def load_forecasts() -> tuple[pd.DataFrame, pd.DataFrame]:
    forecasts = query_dataframe(
        """
            SELECT *
            FROM market_quant_forecasts
            WHERE model_version = %s
              AND forecast_date = (
                SELECT max(forecast_date) FROM market_quant_forecasts WHERE model_version = %s
              )
            ORDER BY forecast_date, horizon_day, metal_code
        """,
        (MODEL_VERSION, MODEL_VERSION),
    )
    volatility = query_dataframe(
        """
            SELECT metal_code,
                   percentile_cont(0.50) WITHIN GROUP (ORDER BY rolling_std_30d) AS p50,
                   percentile_cont(0.75) WITHIN GROUP (ORDER BY rolling_std_30d) AS p75,
                   max(rolling_std_30d) FILTER (WHERE price_date = (SELECT max(price_date) FROM market_quant_features)) AS latest_std_30d
            FROM market_quant_features
            WHERE rolling_std_30d IS NOT NULL
            GROUP BY metal_code
        """
    )
    return forecasts, volatility


def classify(row: pd.Series) -> tuple[str, str, str]:
    r = float(row["predicted_return"])
    name = row["metal_name"]
    rank = row.get("relative_strength_rank")
    rank_text = "且相对强度排名靠前，" if pd.notna(rank) and int(rank) <= 3 else ""
    if r > 0.05:
        return "高", "提前采购/锁价", f"预计未来30天{name}价格上涨风险较高，{rank_text}建议提前采购并考虑锁价。"
    if r > 0.03:
        return "中高", "建议提前采购", f"预计未来30天{name}价格存在上涨压力，{rank_text}建议适度提前采购。"
    if r >= -0.03:
        return "中", "正常采购", f"预计未来30天{name}价格变化有限，建议按正常周期采购。"
    return "低或下跌风险", "观望/减少库存", f"预计未来30天{name}价格存在下行风险，可适当观望，避免高位囤货。"


def volatility_level(row: pd.Series) -> str:
    latest = row.get("latest_std_30d")
    if pd.isna(latest):
        return "低"
    if pd.notna(row.get("p75")) and latest > row["p75"]:
        return "高"
    if pd.notna(row.get("p50")) and latest > row["p50"]:
        return "中"
    return "低"


def update_rows(rows: list[dict]) -> None:
    sql = """
        UPDATE market_quant_forecasts
        SET volatility_level = %s,
            relative_strength_rank = %s,
            risk_level = %s,
            procurement_signal = %s,
            procurement_advice = %s
        WHERE model_version = %s
          AND forecast_date = %s
          AND metal_code = %s
          AND horizon_day = %s
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(
                sql,
                [
                    (
                        r["volatility_level"], r["relative_strength_rank"], r["risk_level"],
                        r["procurement_signal"], r["procurement_advice"], r["model_version"],
                        r["forecast_date"], r["metal_code"], r["horizon_day"],
                    )
                    for r in rows
                ],
            )
        conn.commit()


def main() -> dict:
    ensure_tables()
    forecasts, volatility = load_forecasts()
    if forecasts.empty:
        raise RuntimeError("No market_quant_forecasts rows available.")
    forecast_30 = forecasts[forecasts["horizon_day"] == 30].copy()
    forecast_30["relative_strength_rank"] = forecast_30.groupby("forecast_date")["predicted_return"].rank(ascending=False, method="first").astype(int)
    forecast_30 = forecast_30.merge(volatility, on="metal_code", how="left")
    updates = []
    for _, row in forecast_30.iterrows():
        risk_level, signal, advice = classify(row)
        updates.append(
            {
                "model_version": row["model_version"],
                "forecast_date": row["forecast_date"],
                "metal_code": row["metal_code"],
                "horizon_day": 30,
                "relative_strength_rank": int(row["relative_strength_rank"]),
                "volatility_level": volatility_level(row),
                "risk_level": risk_level,
                "procurement_signal": signal,
                "procurement_advice": advice,
            }
        )
    update_rows(updates)
    report = {"updated_rows": len(updates), "sample": updates[:10]}
    write_json(Path(__file__).resolve().parent / "procurement_signal_report.json", report)
    log(f"procurement signals updated: {len(updates)}")
    return report


if __name__ == "__main__":
    main()
