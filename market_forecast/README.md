# ToolPilot 金属价格预测页面

这是一个隔离的可运行模块，不改动 ToolPilot 现有 Schema、JSON 数据和参考资源。

## 启动

```powershell
cd C:\Users\Administrator\Desktop\toolsql\ToolPilot
py .\market_forecast\server.py
```

默认页面地址：

```text
http://127.0.0.1:8765/market-forecast
```

数据库连接读取 `C:\Users\Administrator\Desktop\toolsql\.env`，也支持项目根目录 `.env`。使用的环境变量：

```text
PGHOST
PGPORT
PGDATABASE
PGUSER
PGPASSWORD
```

## API

- `GET /api/market/health`
- `GET /api/market/metals`
- `GET /api/market/forecast-batches`
- `GET /api/market/forecast-batches/latest`
- `GET /api/market/history?metal_code=CU&start_date=2025-11-22&end_date=2026-05-21`
- `GET /api/market/forecasts?metal_code=CU&forecast_batch_id=...&start_date=2026-05-22&end_date=2026-08-19`
- `GET /api/market/forecast-summary?metal_code=CU&forecast_batch_id=...`
- `GET /api/market/model-run?metal_code=CU&forecast_batch_id=...`

## 数据来源

- `market_price_history`
- `market_forecast_model_runs`
- `market_price_forecasts`
