from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import MODEL_VERSION, MODULE_DIR, connect, ensure_tables, log, query_dataframe, write_json
else:
    from .common import MODEL_VERSION, MODULE_DIR, connect, ensure_tables, log, query_dataframe, write_json


def load_forecasts() -> pd.DataFrame:
    df = query_dataframe(
        """
        SELECT *
        FROM market_production_forecasts
        WHERE model_version = %s
          AND forecast_date = (
            SELECT max(forecast_date) FROM market_production_forecasts WHERE model_version = %s
          )
        ORDER BY metal_code, horizon_day
        """,
        (MODEL_VERSION, MODEL_VERSION),
    )
    if df.empty:
        raise RuntimeError("No market_production_forecasts rows available.")
    return df


def base_signal(r: float) -> tuple[str, str]:
    if r >= 0.05:
        return "高上涨风险", "提前采购/锁价"
    if r >= 0.03:
        return "中高上涨风险", "建议提前采购"
    if r >= -0.02:
        return "正常波动", "正常采购"
    if r >= -0.05:
        return "下跌风险", "谨慎采购/适度观望"
    return "明显下跌风险", "观望/减少库存"


def apply_metal_signal_override(
    metal_code: str,
    final_predicted_return: float,
    relative_strength_rank: int | None,
    total_metals: int,
    risk_level: str,
    procurement_signal: str,
) -> tuple[str, str]:
    if (
        metal_code == "NI"
        and -0.02 <= final_predicted_return < 0
        and relative_strength_rank is not None
        and relative_strength_rank > max(0, total_metals - 2)
    ):
        return "正常波动", "正常采购/谨慎补库"
    return risk_level, procurement_signal


def build_advice(row: pd.Series, all_horizons: pd.DataFrame, total_metals: int) -> str:
    r30 = float(row["final_predicted_return"])
    risk_level, procurement_signal = base_signal(r30)
    rank = int(row["relative_strength_rank"]) if pd.notna(row["relative_strength_rank"]) else None
    risk_level, procurement_signal = apply_metal_signal_override(
        row["metal_code"],
        r30,
        rank,
        total_metals,
        risk_level,
        procurement_signal,
    )
    name = row["metal_name"]
    advice = [f"{name}30天行情预测信号为{r30:.2%}，风险等级为{risk_level}，建议{procurement_signal}。"]
    if rank is not None and rank <= 2 and r30 < 0.03:
        advice.append("相对强度排名靠前，但预测涨幅尚未达到提前采购阈值，建议正常采购并提前询价/重点关注。")
    elif rank is not None and rank <= 2:
        advice.append("该金属相对强度排名靠前，报价上行压力可能高于其他材料。")
    if 0.02 <= r30 < 0.03:
        advice.append("接近提前采购阈值，可提前询价并关注后续行情。")
    if -0.03 <= r30 < -0.02:
        advice.append("接近下跌风险阈值，建议谨慎采购，避免高位囤货。")
    if rank is not None and rank > max(0, total_metals - 2):
        advice.append("相对走势偏弱，可避免高位囤货。")
    if row.get("volatility_level") == "高":
        advice.append("当前波动率较高，建议分批采购或分批锁价。")
    p10 = row.get("predicted_return_p10")
    p90 = row.get("predicted_return_p90")
    if pd.notna(p10) and float(p10) > 0:
        advice.append("预测区间整体偏上行，上涨风险更稳定。")
    elif pd.notna(p10) and pd.notna(p90) and float(p10) < 0 < float(p90):
        advice.append("预测区间跨越零点，不确定性较高，建议分批决策。")
    metal_rows = all_horizons[all_horizons["metal_code"] == row["metal_code"]].set_index("horizon_day")
    if {7, 30, 90}.issubset(set(metal_rows.index)):
        r7 = float(metal_rows.loc[7, "final_predicted_return"])
        r90 = float(metal_rows.loc[90, "final_predicted_return"])
        if r7 < 0 and r30 > 0 and r90 > 0:
            advice.append("短期可观望，中期准备提前采购或锁价。")
        if r7 > 0 and r30 > 0 and r90 < 0:
            advice.append("短期存在价格压力，但不建议长期大量囤货。")
    return "".join(advice)


def update_rows(rows: list[dict]) -> None:
    sql = """
        UPDATE market_production_forecasts
        SET risk_level = %s,
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
                        r["risk_level"],
                        r["procurement_signal"],
                        r["procurement_advice"],
                        r["model_version"],
                        r["forecast_date"],
                        r["metal_code"],
                        r["horizon_day"],
                    )
                    for r in rows
                ],
            )
        conn.commit()


def main() -> dict:
    ensure_tables()
    forecasts = load_forecasts()
    forecast_30 = forecasts[forecasts["horizon_day"] == 30].copy()
    total_metals = int(forecast_30["metal_code"].nunique())
    updates = []
    for _, row in forecast_30.iterrows():
        r30 = float(row["final_predicted_return"])
        rank = int(row["relative_strength_rank"]) if pd.notna(row["relative_strength_rank"]) else None
        risk_level, procurement_signal = base_signal(r30)
        risk_level, procurement_signal = apply_metal_signal_override(
            row["metal_code"],
            r30,
            rank,
            total_metals,
            risk_level,
            procurement_signal,
        )
        updates.append(
            {
                "model_version": row["model_version"],
                "forecast_date": row["forecast_date"],
                "metal_code": row["metal_code"],
                "horizon_day": 30,
                "risk_level": risk_level,
                "procurement_signal": procurement_signal,
                "procurement_advice": build_advice(row, forecasts, total_metals),
            }
        )
    update_rows(updates)
    report = {"updated_rows": len(updates), "sample": updates[:10]}
    write_json(MODULE_DIR / "production_procurement_signal_report.json", report)
    log(f"production procurement signals updated: {len(updates)}")
    return report


if __name__ == "__main__":
    main()
