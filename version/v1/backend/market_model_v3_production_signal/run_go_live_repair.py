from __future__ import annotations

import sys
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal import (
        build_factor_features,
        build_production_panel_dataset,
        collect_factor_prices,
        generate_production_procurement_signals,
        predict_production_forecasts,
        train_catboost_excess_models,
        train_quantile_models,
    )
    from backend.market_model_v3_production_signal.common import MODEL_VERSION, REPORT_DIR, connect, ensure_dirs, ensure_tables, log, markdown_table
else:
    from . import (
        build_factor_features,
        build_production_panel_dataset,
        collect_factor_prices,
        generate_production_procurement_signals,
        predict_production_forecasts,
        train_catboost_excess_models,
        train_quantile_models,
    )
    from .common import MODEL_VERSION, REPORT_DIR, connect, ensure_dirs, ensure_tables, log, markdown_table


GO_LIVE_REPORT_PATH = REPORT_DIR / "market_model_v3_production_signal_go_live_report.md"


def fetch_samples() -> dict:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) AS count FROM market_panel_training_dataset")
            panel_count = int(cur.fetchone()["count"])
            cur.execute("SELECT count(DISTINCT metal_code) AS count FROM market_panel_training_dataset")
            metal_count = int(cur.fetchone()["count"])
            cur.execute(
                """
                SELECT DISTINCT factor_code
                FROM market_factor_prices
                ORDER BY factor_code
                """
            )
            factors = [row["factor_code"] for row in cur.fetchall()]
            cur.execute(
                """
                SELECT DISTINCT metal_code, metal_name
                FROM market_panel_training_dataset
                ORDER BY metal_code
                """
            )
            metals = cur.fetchall()
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, horizon_day,
                       final_predicted_return, final_predicted_price,
                       predicted_return_p10, predicted_return_p50, predicted_return_p90,
                       relative_strength_rank, model_reliability_level
                FROM market_production_forecasts
                WHERE model_version = %s
                ORDER BY forecast_date DESC, horizon_day, relative_strength_rank NULLS LAST
                LIMIT 12
                """,
                (MODEL_VERSION,),
            )
            forecast_sample = cur.fetchall()
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, final_predicted_return,
                       relative_strength_rank, volatility_level, risk_level,
                       procurement_signal, procurement_advice, model_reliability_level
                FROM market_production_forecasts
                WHERE model_version = %s AND horizon_day = 30
                ORDER BY forecast_date DESC, relative_strength_rank NULLS LAST
                """,
                (MODEL_VERSION,),
            )
            signals = cur.fetchall()
    return {
        "panel_count": panel_count,
        "metal_count": metal_count,
        "factors": factors,
        "metals": metals,
        "forecast_sample": forecast_sample,
        "signals": signals,
    }


def round_rows(rows: list[dict], numeric_cols: list[str]) -> list[dict]:
    out = []
    for row in rows:
        clean = dict(row)
        for col in numeric_cols:
            if clean.get(col) is not None:
                clean[col] = round(float(clean[col]), 6)
        out.append(clean)
    return out


def write_go_live_report(factor_report: dict, panel_report: dict, catboost_report: dict, quantile_report: dict, prediction_report: dict, signal_report: dict, samples: dict) -> None:
    missing = [{"factor_code": k, "reason": v} for k, v in factor_report.get("missing_factors", {}).items()]
    metals = [{"metal_code": r["metal_code"], "metal_name": r["metal_name"]} for r in samples["metals"]]
    forecast_sample = round_rows(
        samples["forecast_sample"],
        ["final_predicted_return", "final_predicted_price", "predicted_return_p10", "predicted_return_p50", "predicted_return_p90"],
    )
    signal_sample = round_rows(samples["signals"], ["final_predicted_return"])
    normal = [r for r in samples["signals"] if r.get("procurement_signal") == "正常采购"]
    inquiry = [
        r
        for r in samples["signals"]
        if "提前询价" in str(r.get("procurement_advice", "")) or "重点关注" in str(r.get("procurement_advice", ""))
    ]
    cautious = [
        r
        for r in samples["signals"]
        if r.get("procurement_signal") in {"谨慎采购/适度观望", "观望/减少库存"} or "避免高位囤货" in str(r.get("procurement_advice", ""))
    ]
    normal_rows = round_rows(normal, ["final_predicted_return"])
    inquiry_rows = round_rows(inquiry, ["final_predicted_return"])
    cautious_rows = round_rows(cautious, ["final_predicted_return"])
    content = f"""# market_model_v3_production_signal Go-Live Repair Report

## 1. reliability 规则修复差异

修复前：主要按 `data_quality_score` 和区间宽度粗略判定，导致 `predicted_return_p10 < 0 < predicted_return_p90` 时仍可能为“高”。

修复后：
- p10、p50、p90 全部为正：`model_reliability_level = 高`
- p10、p50、p90 全部为负：`model_reliability_level = 高`
- p10 < 0 < p90：最高只能为“中”
- 区间宽度大于该 horizon 既有预测区间宽度 75% 分位：降一级
- WTI/GOLD/DXY/USD_CNY 关键因子缺失超过 50%：降一级
- `data_quality_score < 0.7`：降一级

## 2. 外部因子补齐情况

已接入因子：{", ".join(samples["factors"])}

本次补齐重点：
- `WTI`：从现有宽表 CSV `price_forecast/webscraping_scripts/commodity_futures.csv` 的 `WTI CRUDE` 列接入
- `GOLD`：从同一 CSV 的 `GOLD` 列接入
- `DXY`：未在当前数据库、CSV、Kaggle 表中找到
- `USD_CNY`：未在当前数据库、CSV、Kaggle 表中找到

## 3. 仍然缺失的因子

{markdown_table(missing, ["factor_code", "reason"])}

## 4. 最新入选金属

{markdown_table(metals, ["metal_code", "metal_name"])}

## 5. 最新 panel dataset 样本数

- rows: {samples["panel_count"]}
- metal_count: {samples["metal_count"]}
- date_range: {panel_report.get("date_range")}
- complete_target_rows: {panel_report.get("complete_target_rows")}

## 6. 最新生产版预测样例

{markdown_table(forecast_sample, ["forecast_date", "metal_code", "metal_name", "horizon_day", "final_predicted_return", "final_predicted_price", "predicted_return_p10", "predicted_return_p50", "predicted_return_p90", "relative_strength_rank", "model_reliability_level"])}

## 7. 最新采购信号样例

{markdown_table(signal_sample, ["forecast_date", "metal_code", "metal_name", "final_predicted_return", "relative_strength_rank", "volatility_level", "risk_level", "procurement_signal", "model_reliability_level", "procurement_advice"])}

## 8. 建议正常采购的金属

{markdown_table(normal_rows, ["metal_code", "metal_name", "final_predicted_return", "relative_strength_rank", "procurement_signal", "model_reliability_level"])}

## 9. 建议提前询价的金属

{markdown_table(inquiry_rows, ["metal_code", "metal_name", "final_predicted_return", "relative_strength_rank", "procurement_signal", "model_reliability_level", "procurement_advice"])}

## 10. 建议谨慎采购/观望的金属

{markdown_table(cautious_rows, ["metal_code", "metal_name", "final_predicted_return", "relative_strength_rank", "procurement_signal", "model_reliability_level", "procurement_advice"])}

## 11. API 和前端最终读取表确认

API 和前端最终读取表确认：`market_production_forecasts`。

对应查询入口：
- `GET /api/market/production-forecasts`
- `GET /api/market/production-ranking`
- `GET /api/market/production-detail`
"""
    GO_LIVE_REPORT_PATH.write_text(content, encoding="utf-8")


def main() -> dict:
    ensure_dirs()
    log("step 1/8 ensure production tables")
    db_stats = ensure_tables()
    log("step 2/8 collect minimal external factors")
    factor_report = collect_factor_prices.main()
    log("step 3/8 rebuild factor features")
    factor_feature_report = build_factor_features.main()
    log("step 4/8 rebuild panel dataset")
    panel_report = build_production_panel_dataset.main()
    log("step 5/8 retrain CatBoost excess return models")
    catboost_report = train_catboost_excess_models.main()
    log("step 6/8 retrain quantile interval models")
    quantile_report = train_quantile_models.main()
    log("step 7/8 regenerate production forecasts")
    prediction_report = predict_production_forecasts.main()
    log("step 8/8 regenerate procurement signals and go-live report")
    signal_report = generate_production_procurement_signals.main()
    samples = fetch_samples()
    write_go_live_report(factor_report, panel_report, catboost_report, quantile_report, prediction_report, signal_report, samples)
    log(f"go-live repair report: {GO_LIVE_REPORT_PATH}")
    return {
        "db_stats": db_stats,
        "factor_report": factor_report,
        "factor_feature_report": factor_feature_report,
        "panel_report": panel_report,
        "catboost_report": catboost_report,
        "quantile_report": quantile_report,
        "prediction_report": prediction_report,
        "signal_report": signal_report,
        "report_path": str(GO_LIVE_REPORT_PATH),
    }


if __name__ == "__main__":
    main()

