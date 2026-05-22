# ToolPilot 行情采购信号正式版

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

AL, CO, CU, IRON_ORE, NATURAL_GAS, NI, PB, SN, ZN

## 5. 缺失因子列表及原因

| factor_code | reason |
| --- | --- |
| WTI | no matching existing database rows or CSV source found |
| BRENT | no matching existing database rows or CSV source found |
| GOLD | no matching existing database rows or CSV source found |
| SILVER | no matching existing database rows or CSV source found |
| DXY | no matching existing database rows or CSV source found |
| USD_CNY | no matching existing database rows or CSV source found |
| SP500 | no matching existing database rows or CSV source found |
| NASDAQ | no matching existing database rows or CSV source found |
| CSI300 | no matching existing database rows or CSV source found |
| SHANGHAI_INDEX | no matching existing database rows or CSV source found |

## 6. 入选金属列表

入选金属数：8

## 7. panel dataset 样本数

- rows: 8026
- date_range: ['2022-08-17', '2026-05-21']
- complete_target_rows: {'7': 7970, '30': 7786, '90': 7306}
- no_future_leakage: feature columns are joined by price_date from same-day or earlier rolling features; targets are stored separately and excluded from model feature_columns

## 8. CatBoost excess return 模型路径

| horizon_day | sample_count | metal_count | feature_count | model_path | train_status |
| --- | --- | --- | --- | --- | --- |
| 7 | 7970 | 8 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\catboost_excess_return_7d.cbm | success |
| 30 | 7786 | 8 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\catboost_excess_return_30d.cbm | success |
| 90 | 7306 | 8 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\catboost_excess_return_90d.cbm | success |

## 9. quantile 区间模型路径

| model | sample_count | feature_count | model_path | train_status |
| --- | --- | --- | --- | --- |
| 7_p10 | 7970 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_7d_p10.pkl | success |
| 7_p50 | 7970 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_7d_p50.pkl | success |
| 7_p90 | 7970 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_7d_p90.pkl | success |
| 30_p10 | 7786 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_30d_p10.pkl | success |
| 30_p50 | 7786 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_30d_p50.pkl | success |
| 30_p90 | 7786 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_30d_p90.pkl | success |
| 90_p10 | 7306 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_90d_p10.pkl | success |
| 90_p50 | 7306 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_90d_p50.pkl | success |
| 90_p90 | 7306 | 32 | C:\Users\Administrator\Desktop\toolsql\MITSUI\backend\models\market_model_v3_production_signal\quantile_return_90d_p90.pkl | success |

## 10. 生产版预测样例

| forecast_date | metal_code | metal_name | horizon_day | base_price | final_predicted_return | final_predicted_price | predicted_return_p10 | predicted_return_p50 | predicted_return_p90 | relative_strength_rank | model_reliability_level |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | SN | 锡 | 7 | 404280.000000 | 0.011094 | 408764.9 | -0.020902 | -0.005827 | 0.050523 | 1 | 高 |
| 2026-05-21 | CO | 钴 | 7 | 426200.000000 | 0.00934 | 430180.58 | -0.0143 | -0.00193 | 0.01426 | 2 | 高 |
| 2026-05-21 | NI | 镍 | 7 | 143233.330000 | 0.005669 | 144045.39 | -0.017106 | 0.002348 | 0.027177 | 3 | 高 |
| 2026-05-21 | CU | 铜 | 7 | 103398.330000 | 0.00473 | 103887.41 | -0.009579 | -0.002135 | 0.02046 | 4 | 高 |
| 2026-05-21 | PB | 铅 | 7 | 16315.000000 | 0.004725 | 16392.09 | -0.005474 | 0.004102 | 0.012198 | 5 | 高 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | 7 | 784.000000 | 0.002964 | 786.32 | -0.015856 | 0.001637 | 0.018545 | 6 | 高 |
| 2026-05-21 | ZN | 锌 | 7 | 24440.000000 | 0.00125 | 24470.56 | -0.012477 | -0.002686 | 0.014408 | 7 | 高 |
| 2026-05-21 | AL | 铝 | 7 | 24210.000000 | -0.000318 | 24202.31 | -0.011983 | 0.003897 | 0.017572 | 8 | 高 |
| 2026-05-21 | SN | 锡 | 30 | 404280.000000 | 0.022933 | 413551.4 | -0.021823 | 0.023361 | 0.085478 | 1 | 中 |
| 2026-05-21 | CU | 铜 | 30 | 103398.330000 | 0.008182 | 104244.34 | -0.015228 | 0.01083 | 0.035916 | 2 | 高 |

## 11. 生产版采购信号样例

| forecast_date | metal_code | metal_name | final_predicted_return | relative_strength_rank | volatility_level | risk_level | procurement_signal | procurement_advice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | SN | 锡 | 0.022933 | 1 | 低 | 正常波动 | 正常采购 | 锡30天预测收益率为2.29%，风险等级为正常波动，建议正常采购。该金属相对强度排名靠前，报价上行压力可能高于其他材料。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | CU | 铜 | 0.008182 | 2 | 低 | 正常波动 | 正常采购 | 铜30天预测收益率为0.82%，风险等级为正常波动，建议正常采购。该金属相对强度排名靠前，报价上行压力可能高于其他材料。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | PB | 铅 | 0.006328 | 3 | 低 | 正常波动 | 正常采购 | 铅30天预测收益率为0.63%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。短期存在价格压力，但不建议长期大量囤货。 |
| 2026-05-21 | AL | 铝 | 0.001944 | 4 | 低 | 正常波动 | 正常采购 | 铝30天预测收益率为0.19%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。短期可观望，中期准备提前采购或锁价。 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | -0.001574 | 5 | 低 | 正常波动 | 正常采购 | 铁矿石澳30天预测收益率为-0.16%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | NI | 镍 | -0.011993 | 6 | 低 | 正常波动 | 正常采购 | 镍30天预测收益率为-1.20%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | ZN | 锌 | -0.013976 | 7 | 低 | 正常波动 | 正常采购 | 锌30天预测收益率为-1.40%，风险等级为正常波动，建议正常采购。该金属相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | CO | 钴 | -0.026359 | 8 | 低 | 下跌风险 | 谨慎采购/适度观望 | 钴30天预测收益率为-2.64%，风险等级为下跌风险，建议谨慎采购/适度观望。该金属相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |

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
