# market_model_v3_quant_signal Implementation Report

## 1. 本次实现目标

实现 ToolPilot 行情预测与采购风险信号模块 `market_model_v3_quant_signal`，将收益率特征、跨金属 pair/spread 特征、LightGBM direct horizon 模型、预测结果和采购建议写入 PostgreSQL，供后续 API 和前端调用。

## 2. MITSUI-inspired 思路说明

- 不直接预测未来绝对价格，训练目标为未来 7/30/90 天收益率。
- 使用 ToolPilot 业务周期 7 天、30 天、90 天，不使用递归预测。
- 构造跨金属相对强弱和 pair/spread 特征，服务金属间强弱排序。
- 输出 rank IC 指标和 30 天采购风险信号，重点服务采购建议。

## 3. 数据来源表

实际使用来源表：`market_price_history`。

## 4. 入选金属列表

CU, NI, CO, AL, IRON_ORE, PB, SN, ZN

## 5. 被剔除金属及原因

_No rows._

## 6. 特征字段覆盖率

- close_price: 1.0
- drawdown_30d: 0.9711
- drawdown_90d: 0.9113
- industrial_avg_return_30d: 0.9708
- industrial_avg_return_7d: 0.993
- industrial_avg_return_90d: 0.911
- momentum_30d: 0.9711
- momentum_7d: 0.994
- momentum_90d: 0.9113
- pct_rank_30d: 0.9711
- pct_rank_90d: 0.9113
- relative_strength_30d: 0.9701
- relative_strength_7d: 0.993
- relative_strength_90d: 0.9103
- return_14d: 0.986
- return_1d: 0.999
- return_30d: 0.9701
- return_3d: 0.997
- return_60d: 0.9402
- return_7d: 0.993
- return_90d: 0.9103
- rolling_mean_14d: 0.987
- rolling_mean_30d: 0.9711
- rolling_mean_60d: 0.9412
- rolling_mean_7d: 0.994
- rolling_mean_90d: 0.9113
- rolling_std_14d: 0.986
- rolling_std_30d: 0.9701
- rolling_std_60d: 0.9402
- rolling_std_7d: 0.993
- rolling_std_90d: 0.9103
- target_direction_30d: 0.9701
- target_direction_7d: 0.993
- target_direction_90d: 0.9103
- target_return_30d: 0.9701
- target_return_7d: 0.993
- target_return_90d: 0.9103
- zscore_30d: 0.9711
- zscore_90d: 0.9113

## 7. 模型文件路径

| horizon_day | sample_count | feature_count | mae_return | direction_accuracy | model_path |
| --- | --- | --- | --- | --- | --- |
| 7 | 7250 | 34 | 0.010455 | 0.8403 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3\model_return_7d.pkl |
| 30 | 7066 | 34 | 0.012866 | 0.9089 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3\model_return_30d.pkl |
| 90 | 6586 | 34 | 0.012715 | 0.9335 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3\model_return_90d.pkl |

配置文件：

- `C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3\feature_columns.json`
- `C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3\model_config.json`

## 8. 预测结果样例

| forecast_date | metal_code | metal_name | horizon_day | base_price | predicted_return | predicted_price | predicted_direction | direction_confidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | AL | 铝 | 7 | 24210.000000 | 0.003327 | 24290.56 | 1 | 0.33 |
| 2026-05-21 | CO | 钴 | 7 | 426200.000000 | 0.016617 | 433282.13 | 1 | 0.66 |
| 2026-05-21 | CU | 铜 | 7 | 103398.330000 | 0.006141 | 104033.33 | 1 | 0.33 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | 7 | 784.000000 | 0.005852 | 788.59 | 1 | 0.33 |
| 2026-05-21 | NI | 镍 | 7 | 143233.330000 | 0.006732 | 144197.58 | 1 | 0.33 |
| 2026-05-21 | PB | 铅 | 7 | 16315.000000 | 0.007791 | 16442.11 | 1 | 0.33 |
| 2026-05-21 | SN | 锡 | 7 | 404280.000000 | 0.0107 | 408605.8 | 1 | 0.66 |
| 2026-05-21 | ZN | 锌 | 7 | 24440.000000 | 0.002258 | 24495.19 | 1 | 0.33 |
| 2026-05-21 | AL | 铝 | 30 | 24210.000000 | 0.011165 | 24480.3 | 1 | 0.66 |
| 2026-05-21 | CO | 钴 | 30 | 426200.000000 | -0.041805 | 408382.86 | 0 | 0.9 |

## 9. 采购信号样例

| forecast_date | metal_code | metal_name | predicted_return | relative_strength_rank | volatility_level | risk_level | procurement_signal | procurement_advice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | SN | 锡 | 0.034377 | 1 | 中 | 中高 | 建议提前采购 | 预计未来30天锡价格存在上涨压力，且相对强度排名靠前，建议适度提前采购。 |
| 2026-05-21 | CU | 铜 | 0.027294 | 2 | 中 | 中 | 正常采购 | 预计未来30天铜价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | PB | 铅 | 0.02259 | 3 | 低 | 中 | 正常采购 | 预计未来30天铅价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | 0.011257 | 4 | 低 | 中 | 正常采购 | 预计未来30天铁矿石澳价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | AL | 铝 | 0.011165 | 5 | 低 | 中 | 正常采购 | 预计未来30天铝价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | ZN | 锌 | 0.000848 | 6 | 低 | 中 | 正常采购 | 预计未来30天锌价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | NI | 镍 | -0.029983 | 7 | 中 | 中 | 正常采购 | 预计未来30天镍价格变化有限，建议按正常周期采购。 |
| 2026-05-21 | CO | 钴 | -0.041805 | 8 | 低 | 低或下跌风险 | 观望/减少库存 | 预计未来30天钴价格存在下行风险，可适当观望，避免高位囤货。 |

## 10. 数据库写入统计

| table | rows |
| --- | --- |
| market_quant_features | 8026 |
| market_pair_features | 4013 |
| market_model_versions current version | 3 |
| market_quant_forecasts current version | 24 |

本次 upsert：

- quant features: 8026
- pair features: 4013
- forecasts: 24
- procurement signal updates: 8

## 11. API / 前端后续接入建议

- 新增 `GET /api/market/quant-forecasts?model_version=v3_20260522&horizon_day=30` 返回预测和采购信号。
- 新增 `GET /api/market/quant-features?metal_code=CU` 支持特征诊断页。
- 前端优先展示 30 天采购信号，7/90 天作为趋势辅助视图。
- 在金属详情页加入相对强弱排名、波动率等级和 pair/spread 对比。

## 12. 当前限制

- 不是复现 MITSUI 官方模型。
- 当前为 ToolPilot 业务周期 7/30/90 天。
- 当前模型只作为采购风险信号，不作为金融交易建议。
- 后续可加入 CatBoost、XGBoost、quantile prediction 和置信区间。
