from __future__ import annotations

import sys
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3 import build_pair_features, build_quant_features, generate_procurement_signals, predict_quant_signals, train_quant_signal_models
    from backend.market_model_v3.common import MODEL_DIR, MODEL_NAME, MODEL_VERSION, REPORT_PATH, connect, ensure_dirs, ensure_tables, log
else:
    from . import build_pair_features, build_quant_features, generate_procurement_signals, predict_quant_signals, train_quant_signal_models
    from .common import MODEL_DIR, MODEL_NAME, MODEL_VERSION, REPORT_PATH, connect, ensure_dirs, ensure_tables, log


def fetch_samples() -> dict:
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS count FROM market_quant_features")
            quant_count = cur.fetchone()["count"]
            cur.execute("SELECT COUNT(*) AS count FROM market_pair_features")
            pair_count = cur.fetchone()["count"]
            cur.execute("SELECT COUNT(*) AS count FROM market_model_versions WHERE model_version=%s", (MODEL_VERSION,))
            version_count = cur.fetchone()["count"]
            cur.execute("SELECT COUNT(*) AS count FROM market_quant_forecasts WHERE model_version=%s", (MODEL_VERSION,))
            forecast_count = cur.fetchone()["count"]
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, horizon_day, base_price,
                       predicted_return, predicted_price, predicted_direction, direction_confidence
                FROM market_quant_forecasts
                WHERE model_version=%s
                ORDER BY forecast_date DESC, horizon_day, metal_code
                LIMIT 10
                """,
                (MODEL_VERSION,),
            )
            forecast_sample = cur.fetchall()
            cur.execute(
                """
                SELECT forecast_date, metal_code, metal_name, predicted_return, relative_strength_rank,
                       volatility_level, risk_level, procurement_signal, procurement_advice
                FROM market_quant_forecasts
                WHERE model_version=%s AND horizon_day=30
                ORDER BY forecast_date DESC, relative_strength_rank NULLS LAST
                LIMIT 10
                """,
                (MODEL_VERSION,),
            )
            signal_sample = cur.fetchall()
    return {
        "market_quant_features": int(quant_count),
        "market_pair_features": int(pair_count),
        "market_model_versions": int(version_count),
        "market_quant_forecasts": int(forecast_count),
        "forecast_sample": forecast_sample,
        "signal_sample": signal_sample,
    }


def markdown_table(rows: list[dict], columns: list[str]) -> str:
    if not rows:
        return "_No rows._"
    lines = ["| " + " | ".join(columns) + " |", "| " + " | ".join(["---"] * len(columns)) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(row.get(c, "")) for c in columns) + " |")
    return "\n".join(lines)


def write_implementation_report(quant: dict, pair: dict, train: dict, predict: dict, procurement: dict, db_stats: dict, table_stats: dict) -> None:
    forecast_rows = [
        {
            **row,
            "predicted_return": round(float(row["predicted_return"]), 6),
            "predicted_price": round(float(row["predicted_price"]), 2),
        }
        for row in table_stats["forecast_sample"]
    ]
    signal_rows = [
        {
            **row,
            "predicted_return": round(float(row["predicted_return"]), 6),
        }
        for row in table_stats["signal_sample"]
    ]
    horizon_rows = []
    for horizon, info in train.get("horizons", {}).items():
        horizon_rows.append(
            {
                "horizon_day": horizon,
                "sample_count": info.get("sample_count"),
                "feature_count": info.get("feature_count"),
                "mae_return": round(float(info.get("mae_return") or 0), 6),
                "direction_accuracy": round(float(info.get("direction_accuracy") or 0), 4),
                "model_path": info.get("model_path"),
            }
        )

    coverage_items = sorted(quant.get("coverage", {}).items())
    coverage_text = "\n".join(f"- {k}: {v}" for k, v in coverage_items)
    content = f"""# market_model_v3_quant_signal Implementation Report

## 1. 本次实现目标

实现 ToolPilot 行情预测与采购风险信号模块 `market_model_v3_quant_signal`，将收益率特征、跨金属 pair/spread 特征、LightGBM direct horizon 模型、预测结果和采购建议写入 PostgreSQL，供后续 API 和前端调用。

## 2. MITSUI-inspired 思路说明

- 不直接预测未来绝对价格，训练目标为未来 7/30/90 天收益率。
- 使用 ToolPilot 业务周期 7 天、30 天、90 天，不使用递归预测。
- 构造跨金属相对强弱和 pair/spread 特征，服务金属间强弱排序。
- 输出 rank IC 指标和 30 天采购风险信号，重点服务采购建议。

## 3. 数据来源表

实际使用来源表：`{quant.get("source_table")}`。

## 4. 入选金属列表

{", ".join(quant.get("selected_metals", []))}

## 5. 被剔除金属及原因

{markdown_table([{"metal_code": k, "reason": v} for k, v in quant.get("skipped_metals", {}).items()], ["metal_code", "reason"])}

## 6. 特征字段覆盖率

{coverage_text}

## 7. 模型文件路径

{markdown_table(horizon_rows, ["horizon_day", "sample_count", "feature_count", "mae_return", "direction_accuracy", "model_path"])}

配置文件：

- `{MODEL_DIR / "feature_columns.json"}`
- `{MODEL_DIR / "model_config.json"}`

## 8. 预测结果样例

{markdown_table(forecast_rows, ["forecast_date", "metal_code", "metal_name", "horizon_day", "base_price", "predicted_return", "predicted_price", "predicted_direction", "direction_confidence"])}

## 9. 采购信号样例

{markdown_table(signal_rows, ["forecast_date", "metal_code", "metal_name", "predicted_return", "relative_strength_rank", "volatility_level", "risk_level", "procurement_signal", "procurement_advice"])}

## 10. 数据库写入统计

| table | rows |
| --- | --- |
| market_quant_features | {table_stats["market_quant_features"]} |
| market_pair_features | {table_stats["market_pair_features"]} |
| market_model_versions current version | {table_stats["market_model_versions"]} |
| market_quant_forecasts current version | {table_stats["market_quant_forecasts"]} |

本次 upsert：

- quant features: {quant.get("upserted_rows")}
- pair features: {pair.get("upserted_rows")}
- forecasts: {predict.get("upserted_rows")}
- procurement signal updates: {procurement.get("updated_rows")}

## 11. API / 前端后续接入建议

- 新增 `GET /api/market/quant-forecasts?model_version={MODEL_VERSION}&horizon_day=30` 返回预测和采购信号。
- 新增 `GET /api/market/quant-features?metal_code=CU` 支持特征诊断页。
- 前端优先展示 30 天采购信号，7/90 天作为趋势辅助视图。
- 在金属详情页加入相对强弱排名、波动率等级和 pair/spread 对比。

## 12. 当前限制

- 不是复现 MITSUI 官方模型。
- 当前为 ToolPilot 业务周期 7/30/90 天。
- 当前模型只作为采购风险信号，不作为金融交易建议。
- 后续可加入 CatBoost、XGBoost、quantile prediction 和置信区间。
"""
    REPORT_PATH.write_text(content, encoding="utf-8")


def main() -> dict:
    ensure_dirs()
    log("step 1/6 ensure database tables")
    db_stats = ensure_tables()
    log("step 2/6 build quant features")
    quant = build_quant_features.main()
    log("step 3/6 build pair features")
    pair = build_pair_features.main()
    log("step 4/6 train direct horizon models")
    train = train_quant_signal_models.main()
    log("step 5/6 predict quant signals")
    predict = predict_quant_signals.main()
    log("step 6/6 generate procurement signals")
    procurement = generate_procurement_signals.main()
    table_stats = fetch_samples()
    write_implementation_report(quant, pair, train, predict, procurement, db_stats, table_stats)
    log(f"implementation report: {REPORT_PATH}")
    return {
        "db_stats": db_stats,
        "quant": quant,
        "pair": pair,
        "train": train,
        "predict": predict,
        "procurement": procurement,
        "report_path": str(REPORT_PATH),
    }


if __name__ == "__main__":
    main()
