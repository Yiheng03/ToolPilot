# ToolPilot Production 前端接入报告

## 接入结论

- 新增前端页面：`backend/frontend/market_production_dashboard.html`。
- 页面默认读取 `GET /api/market/production-ranking`，优先展示 30 天相对强弱排名。
- 点击金属后读取 `GET /api/market/production-detail` 展示金属详情。
- 页面文案统一使用“行情预测信号”，不把预测输出描述为确定价格。

## 展示内容

金属详情页已覆盖：

- 历史价格曲线
- 7/30/90 天行情预测信号点
- p10/p50/p90 预测区间
- 相对强弱排名
- 风险等级
- `procurement_signal`
- `procurement_advice`
- `model_reliability_level`

## 前端约束

- 页面不展示 `direction_accuracy`。
- 页面不展示模型准确率。
- 页面接口最终依赖 `market_production_forecasts`，通过 production API 获取数据。

## 页面入口

独立 FastAPI 服务入口：

- `/`
- `/market-forecast`

当前本地验证地址：

- `http://127.0.0.1:8765/market-forecast`

## 本次验证

- `GET /market-forecast` 返回 200。
- 页面默认调用 `GET /api/market/production-ranking`。
- 页面点击金属后调用 `GET /api/market/production-detail?metal_code=...`。
- 前端文件静态检查未发现 `direction_accuracy`、模型准确率、确定价格或预测价格展示文案。
