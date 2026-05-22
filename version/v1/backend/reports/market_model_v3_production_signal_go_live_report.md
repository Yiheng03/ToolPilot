# market_model_v3_production_signal Go-Live Repair Report

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

已接入因子：AL, BRENT, CO, CU, GOLD, IRON_ORE, NATURAL_GAS, NI, PB, SILVER, SN, WTI, ZN

本次补齐重点：
- `WTI`：从现有宽表 CSV `price_forecast/webscraping_scripts/commodity_futures.csv` 的 `WTI CRUDE` 列接入
- `GOLD`：从同一 CSV 的 `GOLD` 列接入
- `DXY`：未在当前数据库、CSV、Kaggle 表中找到
- `USD_CNY`：未在当前数据库、CSV、Kaggle 表中找到

## 3. 仍然缺失的因子

| factor_code | reason |
| --- | --- |
| DXY | no matching existing database rows or CSV source found |
| USD_CNY | no matching existing database rows or CSV source found |
| SP500 | no matching existing database rows or CSV source found |
| NASDAQ | no matching existing database rows or CSV source found |
| CSI300 | no matching existing database rows or CSV source found |
| SHANGHAI_INDEX | no matching existing database rows or CSV source found |

## 4. 最新入选金属

| metal_code | metal_name |
| --- | --- |
| AL | 铝 |
| CO | 钴 |
| CU | 铜 |
| IRON_ORE | 铁矿石澳 |
| NI | 镍 |
| PB | 铅 |
| SN | 锡 |
| ZN | 锌 |

## 5. 最新 panel dataset 样本数

- rows: 8026
- metal_count: 8
- date_range: ['2022-08-17', '2026-05-21']
- complete_target_rows: {'7': 7970, '30': 7786, '90': 7306}

## 6. 最新生产版预测样例

| forecast_date | metal_code | metal_name | horizon_day | final_predicted_return | final_predicted_price | predicted_return_p10 | predicted_return_p50 | predicted_return_p90 | relative_strength_rank | model_reliability_level |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | SN | 锡 | 7 | 0.011826 | 409061.193159 | -0.020552 | -0.000181 | 0.05579 | 1 | 低 |
| 2026-05-21 | CO | 钴 | 7 | 0.008736 | 429923.335764 | -0.015201 | -0.002595 | 0.013887 | 2 | 中 |
| 2026-05-21 | PB | 铅 | 7 | 0.005233 | 16400.377177 | -0.004495 | 0.003393 | 0.008877 | 3 | 中 |
| 2026-05-21 | NI | 镍 | 7 | 0.005122 | 143967.040533 | -0.017697 | -0.003529 | 0.031177 | 4 | 低 |
| 2026-05-21 | CU | 铜 | 7 | 0.003599 | 103770.50069 | -0.008983 | -0.00285 | 0.017271 | 5 | 中 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | 7 | 0.00244 | 785.913202 | -0.016009 | -0.000259 | 0.016987 | 6 | 中 |
| 2026-05-21 | ZN | 锌 | 7 | 0.000523 | 24452.790247 | -0.013368 | -0.004488 | 0.015533 | 7 | 中 |
| 2026-05-21 | AL | 铝 | 7 | -0.001239 | 24180.015683 | -0.010897 | -0.000721 | 0.011997 | 8 | 中 |
| 2026-05-21 | SN | 锡 | 30 | 0.023833 | 413915.19001 | -0.012322 | 0.02618 | 0.073739 | 1 | 低 |
| 2026-05-21 | PB | 铅 | 30 | 0.011444 | 16501.709098 | -0.000789 | 0.006008 | 0.024122 | 2 | 中 |
| 2026-05-21 | CU | 铜 | 30 | 0.008348 | 104261.484831 | -0.014727 | 0.003234 | 0.036941 | 3 | 中 |
| 2026-05-21 | AL | 铝 | 30 | 0.003394 | 24292.173766 | -0.00485 | 0.007038 | 0.042113 | 4 | 中 |

## 7. 最新采购信号样例

| forecast_date | metal_code | metal_name | final_predicted_return | relative_strength_rank | volatility_level | risk_level | procurement_signal | model_reliability_level | procurement_advice |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-21 | SN | 锡 | 0.023833 | 1 | 低 | 正常波动 | 正常采购 | 低 | 锡30天预测收益率为2.38%，风险等级为正常波动，建议正常采购。相对强度排名靠前，但预测涨幅尚未达到提前采购阈值，建议正常采购并提前询价/重点关注。接近提前采购阈值，可提前询价并关注后续行情。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | PB | 铅 | 0.011444 | 2 | 低 | 正常波动 | 正常采购 | 中 | 铅30天预测收益率为1.14%，风险等级为正常波动，建议正常采购。相对强度排名靠前，但预测涨幅尚未达到提前采购阈值，建议正常采购并提前询价/重点关注。预测区间跨越零点，不确定性较高，建议分批决策。短期存在价格压力，但不建议长期大量囤货。 |
| 2026-05-21 | CU | 铜 | 0.008348 | 3 | 低 | 正常波动 | 正常采购 | 中 | 铜30天预测收益率为0.83%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | AL | 铝 | 0.003394 | 4 | 低 | 正常波动 | 正常采购 | 中 | 铝30天预测收益率为0.34%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。短期可观望，中期准备提前采购或锁价。 |
| 2026-05-21 | IRON_ORE | 铁矿石澳 | -0.000508 | 5 | 低 | 正常波动 | 正常采购 | 中 | 铁矿石澳30天预测收益率为-0.05%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | ZN | 锌 | -0.010985 | 6 | 低 | 正常波动 | 正常采购 | 中 | 锌30天预测收益率为-1.10%，风险等级为正常波动，建议正常采购。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | NI | 镍 | -0.013629 | 7 | 低 | 正常波动 | 正常采购 | 中 | 镍30天预测收益率为-1.36%，风险等级为正常波动，建议正常采购。相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |
| 2026-05-21 | CO | 钴 | -0.025208 | 8 | 低 | 下跌风险 | 谨慎采购/适度观望 | 低 | 钴30天预测收益率为-2.52%，风险等级为下跌风险，建议谨慎采购/适度观望。接近下跌风险阈值，建议谨慎采购，避免高位囤货。相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |

## 8. 建议正常采购的金属

| metal_code | metal_name | final_predicted_return | relative_strength_rank | procurement_signal | model_reliability_level |
| --- | --- | --- | --- | --- | --- |
| SN | 锡 | 0.023833 | 1 | 正常采购 | 低 |
| PB | 铅 | 0.011444 | 2 | 正常采购 | 中 |
| CU | 铜 | 0.008348 | 3 | 正常采购 | 中 |
| AL | 铝 | 0.003394 | 4 | 正常采购 | 中 |
| IRON_ORE | 铁矿石澳 | -0.000508 | 5 | 正常采购 | 中 |
| ZN | 锌 | -0.010985 | 6 | 正常采购 | 中 |
| NI | 镍 | -0.013629 | 7 | 正常采购 | 中 |

## 9. 建议提前询价的金属

| metal_code | metal_name | final_predicted_return | relative_strength_rank | procurement_signal | model_reliability_level | procurement_advice |
| --- | --- | --- | --- | --- | --- | --- |
| SN | 锡 | 0.023833 | 1 | 正常采购 | 低 | 锡30天预测收益率为2.38%，风险等级为正常波动，建议正常采购。相对强度排名靠前，但预测涨幅尚未达到提前采购阈值，建议正常采购并提前询价/重点关注。接近提前采购阈值，可提前询价并关注后续行情。预测区间跨越零点，不确定性较高，建议分批决策。 |
| PB | 铅 | 0.011444 | 2 | 正常采购 | 中 | 铅30天预测收益率为1.14%，风险等级为正常波动，建议正常采购。相对强度排名靠前，但预测涨幅尚未达到提前采购阈值，建议正常采购并提前询价/重点关注。预测区间跨越零点，不确定性较高，建议分批决策。短期存在价格压力，但不建议长期大量囤货。 |

## 10. 建议谨慎采购/观望的金属

| metal_code | metal_name | final_predicted_return | relative_strength_rank | procurement_signal | model_reliability_level | procurement_advice |
| --- | --- | --- | --- | --- | --- | --- |
| NI | 镍 | -0.013629 | 7 | 正常采购 | 中 | 镍30天预测收益率为-1.36%，风险等级为正常波动，建议正常采购。相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |
| CO | 钴 | -0.025208 | 8 | 谨慎采购/适度观望 | 低 | 钴30天预测收益率为-2.52%，风险等级为下跌风险，建议谨慎采购/适度观望。接近下跌风险阈值，建议谨慎采购，避免高位囤货。相对走势偏弱，可避免高位囤货。预测区间跨越零点，不确定性较高，建议分批决策。 |

## 11. API 和前端最终读取表确认

API 和前端最终读取表确认：`market_production_forecasts`。

对应查询入口：
- `GET /api/market/production-forecasts`
- `GET /api/market/production-ranking`
- `GET /api/market/production-detail`
