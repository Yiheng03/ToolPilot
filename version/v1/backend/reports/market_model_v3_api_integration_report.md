# ToolPilot Production API 接入报告

## 接入结论

- 已确认并接入 `GET /api/market/production-forecasts`。
- 已确认并接入 `GET /api/market/production-ranking`。
- 已确认并接入 `GET /api/market/production-detail`。
- 三个接口最终读取源均为 `market_production_forecasts`。
- 前端/API 不返回 `direction_accuracy`，也不展示模型准确率。

## 数据源约束

`backend/market_model_v3_production_signal/api.py` 已将详情页历史曲线改为从 `market_production_forecasts` 按 `forecast_date` 聚合 `base_price` 生成，不再读取 `market_quant_features`。

## 返回字段

- `production-forecasts`：返回指定模型版本、日期、金属和 horizon 的 production forecast 明细。
- `production-ranking`：固定读取 30 天 horizon，并按 `relative_strength_rank` 输出首页/行情页排名。
- `production-detail`：返回单金属历史价格曲线、7/30/90 天行情预测信号点、p10/p50/p90 区间、相对强弱排名、风险等级、`procurement_signal`、`procurement_advice`、`model_reliability_level`。

## 运行入口

可挂载 `backend.market_model_v3_production_signal.api:router`。

独立运行可使用：

```bash
uvicorn backend.market_model_v3_production_signal.server:app --host 127.0.0.1 --port 8765
```

## 本次验证

- Python 语法检查通过：`api.py`、`server.py`、`generate_production_procurement_signals.py`。
- `GET /api/market/production-ranking` 返回 200，30 天 ranking 行数为 8。
- `GET /api/market/production-forecasts?horizon_day=30` 返回 200，行数为 8。
- `GET /api/market/production-detail?metal_code=NI` 返回 200，包含 `history`、`forecasts`、`metal_code`。
- NI 30 天信号已写入数据库：`final_predicted_return = -0.013629074410525379`，`relative_strength_rank = 7`，`procurement_signal = 正常采购/谨慎补库`。
