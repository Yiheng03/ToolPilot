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
    from backend.market_model_v3_production_signal.common import MODEL_DIR, MODEL_VERSION, REPORT_PATH, connect, ensure_dirs, ensure_tables, log, markdown_table
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
    from .common import MODEL_DIR, MODEL_VERSION, REPORT_PATH, connect, ensure_dirs, ensure_tables, log, markdown_table


def fetch_report_samples() -> dict:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) AS count FROM market_panel_training_dataset")
            panel_count = int(cur.fetchone()["count"])
            cur.execute("SELECT count(DISTINCT metal_code) AS count FROM market_panel_training_dataset")
            metal_count = int(cur.fetchone()["count"])
            cur.execute("SELECT count(DISTINCT factor_code) AS count FROM market_factor_prices")
            factor_count = int(cur.fetchone()["count"])
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, horizon_day, base_price,
                       final_predicted_return, final_predicted_price,
                       predicted_return_p10, predicted_return_p50, predicted_return_p90,
                       relative_strength_rank, model_reliability_level
                FROM market_production_forecasts
                WHERE model_version = %s
                ORDER BY forecast_date DESC, horizon_day, relative_strength_rank NULLS LAST
                LIMIT 10
                """,
                (MODEL_VERSION,),
            )
            forecast_sample = cur.fetchall()
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, final_predicted_return,
                       relative_strength_rank, volatility_level, risk_level,
                       procurement_signal, procurement_advice
                FROM market_production_forecasts
                WHERE model_version = %s AND horizon_day = 30
                ORDER BY forecast_date DESC, relative_strength_rank NULLS LAST
                LIMIT 10
                """,
                (MODEL_VERSION,),
            )
            signal_sample = cur.fetchall()
    return {
        "panel_count": panel_count,
        "metal_count": metal_count,
        "factor_count": factor_count,
        "forecast_sample": forecast_sample,
        "signal_sample": signal_sample,
    }


def write_report(factor_prices: dict, factor_features: dict, panel: dict, catboost: dict, quantile: dict, prediction: dict, signals: dict, samples: dict) -> None:
    forecast_rows = [
        {
            **row,
            "final_predicted_return": round(float(row["final_predicted_return"]), 6) if row.get("final_predicted_return") is not None else "",
            "final_predicted_price": round(float(row["final_predicted_price"]), 2) if row.get("final_predicted_price") is not None else "",
            "predicted_return_p10": round(float(row["predicted_return_p10"]), 6) if row.get("predicted_return_p10") is not None else "",
            "predicted_return_p50": round(float(row["predicted_return_p50"]), 6) if row.get("predicted_return_p50") is not None else "",
            "predicted_return_p90": round(float(row["predicted_return_p90"]), 6) if row.get("predicted_return_p90") is not None else "",
        }
        for row in samples["forecast_sample"]
    ]
    signal_rows = [
        {
            **row,
            "final_predicted_return": round(float(row["final_predicted_return"]), 6) if row.get("final_predicted_return") is not None else "",
        }
        for row in samples["signal_sample"]
    ]
    cat_rows = [
        {
            "horizon_day": horizon,
            "sample_count": info.get("sample_count"),
            "metal_count": info.get("metal_count"),
            "feature_count": info.get("feature_count"),
            "model_path": info.get("model_path"),
            "train_status": info.get("train_status"),
        }
        for horizon, info in catboost.get("horizons", {}).items()
    ]
    quant_rows = [
        {
            "model": key,
            "sample_count": info.get("sample_count"),
            "feature_count": info.get("feature_count"),
            "model_path": info.get("model_path"),
            "train_status": info.get("train_status"),
        }
        for key, info in quantile.get("models", {}).items()
    ]
    missing_rows = [{"factor_code": k, "reason": v} for k, v in factor_prices.get("missing_factors", {}).items()]
    content = f"""# ToolPilot 行情采购信号正式版

## 1. 本次上线版目标

实现 `market_model_v3_production_signal`，中文名称为 ToolPilot 行情采购信号正式版。该模块面向 API 和前端正式读取，最终读取表为 `market_production_forecasts`。

## 2. 与 market_model_v3_quant_signal 的区别

- `market_model_v3_quant_signal` 保留为基础预测层，继续提供 7/30/90 天 LightGBM direct horizon 输出。
- 正式版新增外部市场因子、panel dataset、CatBoost 超额收益模型、quantile 区间模型和 pair/spread 修正。
- 正式版统一使用 `signal_strength`，不把 `direction_confidence` 当概率置信度。

## 3. 已复用的当前成果

- `market_quant_features`
- `market_pair_features`
- `market_model_versions`
- `market_quant_forecasts`
- 当前 7/30/90 天 LightGBM direct horizon 模型输出作为 `pred_lgb_return_7d/30d/90d`

## 4. 新增外部因子列表

{", ".join(factor_prices.get("present_factors", []))}

## 5. 缺失因子列表及原因

{markdown_table(missing_rows, ["factor_code", "reason"])}

## 6. 入选金属列表

入选金属数：{samples["metal_count"]}

## 7. panel dataset 样本数

- rows: {samples["panel_count"]}
- date_range: {panel.get("date_range")}
- complete_target_rows: {panel.get("complete_target_rows")}
- no_future_leakage: {panel.get("no_future_leakage")}

## 8. CatBoost excess return 模型路径

{markdown_table(cat_rows, ["horizon_day", "sample_count", "metal_count", "feature_count", "model_path", "train_status"])}

## 9. quantile 区间模型路径

{markdown_table(quant_rows, ["model", "sample_count", "feature_count", "model_path", "train_status"])}

## 10. 生产版预测样例

{markdown_table(forecast_rows, ["forecast_date", "metal_code", "metal_name", "horizon_day", "base_price", "final_predicted_return", "final_predicted_price", "predicted_return_p10", "predicted_return_p50", "predicted_return_p90", "relative_strength_rank", "model_reliability_level"])}

## 11. 生产版采购信号样例

{markdown_table(signal_rows, ["forecast_date", "metal_code", "metal_name", "final_predicted_return", "relative_strength_rank", "volatility_level", "risk_level", "procurement_signal", "procurement_advice"])}

## 12. API 接入说明

- `GET /api/market/production-forecasts`
- `GET /api/market/production-ranking`
- `GET /api/market/production-detail`

可挂载模块：`backend.market_model_v3_production_signal.api:router`。如果项目没有 FastAPI 服务入口，也可直接调用该模块内的 `get_production_forecasts`、`get_production_ranking`、`get_production_detail`。

## 13. 前端展示建议

- 主列表读取 30 天 `production-ranking`，展示相对强弱排名、风险等级、采购信号和可靠性等级。
- 详情页读取 `production-detail`，展示历史价格、7/30/90 天预测点、p10/p50/p90 区间、关键驱动和采购建议。
- 预测区间用于表达不确定性，不直接替代采购建议。

## 14. 当前版本限制

- 用于采购风险信号，不用于金融交易。
- 外部因子缺失会降低信号质量。
- 预测区间代表不确定性，不是价格承诺。
"""
    REPORT_PATH.write_text(content, encoding="utf-8")


def main() -> dict:
    ensure_dirs()
    log("step 1/9 create production database tables")
    db_stats = ensure_tables()
    log("step 2/9 collect factor prices")
    factor_prices = collect_factor_prices.main()
    log("step 3/9 build factor features")
    factor_features = build_factor_features.main()
    log("step 4/9 build production panel dataset")
    panel = build_production_panel_dataset.main()
    log("step 5/9 train CatBoost excess return models")
    catboost = train_catboost_excess_models.main()
    log("step 6/9 train quantile interval models")
    quantile = train_quantile_models.main()
    log("step 7/9 predict production forecasts")
    prediction = predict_production_forecasts.main()
    log("step 8/9 generate production procurement signals")
    signals = generate_production_procurement_signals.main()
    log("step 9/9 write production implementation report")
    samples = fetch_report_samples()
    write_report(factor_prices, factor_features, panel, catboost, quantile, prediction, signals, samples)
    log(f"production report: {REPORT_PATH}")
    return {
        "db_stats": db_stats,
        "factor_prices": factor_prices,
        "factor_features": factor_features,
        "panel": panel,
        "catboost": catboost,
        "quantile": quantile,
        "prediction": prediction,
        "signals": signals,
        "report_path": str(REPORT_PATH),
        "model_dir": str(MODEL_DIR),
    }


if __name__ == "__main__":
    main()

