# Tool Price Formula V2 Benchmark - 2nd_0525

- 本次评测时间：2026-05-25T09:21:23.621Z
- benchmark 文件路径：C:\Users\Administrator\Desktop\toolsql\MITSUI\ToolPilot\version\v1\tool_quote_benchmark_v1.json
- formulaVersion：tool_price_formula_v2
- 是否接入行情 API：是
- 行情说明：接入本机 production-forecasts，使用 8 条 30 天预测的平均收益率计算 mFuture。
- generatedAnchors：99

## 第一轮 vs 第二轮

| metric | 1st_0525 | 2nd_0525 |
| --- | ---: | ---: |
| MAPE | 59.57% | 47.74% |
| within_30pct_rate | 27.69% | 54.55% |
| interval_hit_rate | 29.23% | 56.06% |
| evaluated_questions / price_evaluated_questions | 65 | 66 |
| quoteAnchors / generatedAnchors | 5 | 99 |

## 总体价格指标

| metric | value |
| --- | ---: |
| total_questions | 100 |
| price_evaluated_questions | 66 |
| ranking_evaluated_questions | 15 |
| skipped_questions | 19 |
| MAPE | 47.74% |
| MdAPE | 27.68% |
| RMSE | 72.979 |
| MAE | 45.1788 |
| mean_signed_percentage_error | 30.02% |
| within_10pct_rate | 19.70% |
| within_20pct_rate | 39.39% |
| within_30pct_rate | 54.55% |
| interval_hit_rate | 56.06% |
| overestimate_rate | 66.67% |
| underestimate_rate | 33.33% |

## Ranking Metrics

| metric | value |
| --- | ---: |
| ranking_evaluated_questions | 15 |
| cheapest_supplier_hit_rate | 33.33% |
| cheapest_category_hit_rate | 38.46% |
| mean_cheapest_price_error | 54.47% |

## 分 level 指标

| group | count | MAPE | MdAPE | within_30pct | interval_hit | mean_signed_pct_error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 35 | 55.06% | 30.88% | 48.57% | 48.57% | 38.54% |
| 2 | 30 | 40.56% | 23.55% | 60.00% | 63.33% | 21.31% |
| 4 | 1 | 6.83% | 6.83% | 100.00% | 100.00% | -6.83% |

## 分 type 指标

| group | count | MAPE | MdAPE | within_30pct | interval_hit | mean_signed_pct_error |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| boundary | 1 | 6.83% | 6.83% | 100.00% | 100.00% | -6.83% |
| exact_match | 35 | 55.06% | 30.88% | 48.57% | 48.57% | 38.54% |
| scenario | 30 | 40.56% | 23.55% | 60.00% | 63.33% | 21.31% |

## Top 20 误差最大样本

| rank | question | category | rawSpec | target | predicted | abs_pct_error | specialToolFactor | matchedAnchors |
| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 常州唐北工具有限公司的D4四刃球刀H7报价是多少？ | 四刃球刀 螺旋铰刀公差H7 | D4*25L*50L*4F | 27.5 | 115.1 | 318.55% | 1 | 3 |
| 2 | 深孔钻削，钻5mm直径的通孔，深度约25mm | 3D钻头（金鹭材料） 5D钻头（金鹭材料） | 1.5-1.6 | 6 | 23.82 | 297.00% | 1 | 5 |
| 3 | 镇江天顺精密工具有限公司的3.175柄 DLC单刃螺旋铣刀报价是多少？ | DLC涂层单刃螺旋铣刀 | 3.175*3.175*12*38 | 13 | 37.95 | 191.92% | 0.55 | 1 |
| 4 | 常州市京锋工具有限公司的D8 3刃铝用加长铣刀报价是多少？ | 3刃铝用铣刀（加长款） | Φ8*35*8*100L 加长款 | 96 | 279.47 | 191.11% | 1 | 5 |
| 5 | 常州唐北工具有限公司的5mm 3D钻头报价是多少？ | 3D钻头（金鹭材料） 5D钻头（金鹭材料） | 4.8-6 | 28 | 62.49 | 123.18% | 1 | 5 |
| 6 | 常州欧成精密工具有限公司的7-8mm铰刀H7报价是多少？ | 数控直柄铰刀 直槽/螺旋 | 7.1-8.0*50*100L*6T H7 | 106 | 233.05 | 119.86% | 1 | 0 |
| 7 | 纯陶瓷铣刀加工，D6*50，用于高温合金 | 55º钨钢铣刀  古铜色涂层 | 6*50 | 59.3 | 120.68 | 103.51% | 1 | 5 |
| 8 | 钻一个M4的台阶孔，180°沉头角度 | 180°台阶钻 | 4.5*18H*8*20H*D8*75L-M4*180° | 126 | 250.28 | 98.63% | 0.75 | 2 |
| 9 | 常州唐北工具有限公司的R0.25 T型刀报价是多少？ | 微小径深沟平刀/球刀 T型刀 | 0.5/R0.25"(2/3/4/6/8) | 24 | 3.22 | 86.58% | 0.45 | 5 |
| 10 | DLC涂层的单刃螺旋铣刀，柄径3.175mm，刃径1.2mm | DLC涂层单刃螺旋铣刀 | 3.175*1.2*3*38 | 13 | 2.95 | 77.31% | 0.55 | 1 |
| 11 | 常州欧成精密工具有限公司的1/2英寸英制球刀报价是多少？ | 数控英制球刀 | 1/2*1-1/4*1/2*3*4F | 180 | 315.39 | 75.22% | 1 | 3 |
| 12 | 常州欧成精密工具有限公司的M3 180°台阶钻报价是多少？ | 180°台阶钻 | 3.4*13H*6.5*15H*6.5D*65L-M3*180° | 162 | 49.55 | 69.41% | 0.75 | 2 |
| 13 | 常州市京锋工具有限公司的D6 2刃键槽铣刀报价是多少？ | 2刃键槽铣刀 | Φ6*15*6*50L | 39 | 65.66 | 68.36% | 1 | 5 |
| 14 | 常州市京锋工具有限公司的R1*D6 内R铣刀(钢用)报价是多少？ | 4刃内R铣刀 | R1*D6*50L*4T 钢用 | 55 | 92.47 | 68.13% | 1 | 0 |
| 15 | 内R角加工，R1*D6，钢件用 | 4刃内R铣刀 | R1*D6*50L*4T 钢用 | 55 | 92.47 | 68.13% | 1 | 0 |
| 16 | 镇江新区大港宏峰工具厂的R6*D12 四刃球刀 55°报价是多少？ | 四刃球刀 | R6*24*12D*100L*4T | 517.99 | 837.26 | 61.64% | 1 | 1 |
| 17 | 在铝合金上铣键槽，槽宽6mm，深度15mm，总长50mm，2刃 | 2刃键槽铣刀 | Φ6*15*6*50L | 39 | 62.38 | 59.95% | 1 | 5 |
| 18 | 高效率粗加工钢件，需要D12动态铣刀，总长75mm | 黑灰动态铣 | D12*75L | 188.9 | 289.71 | 53.37% | 1 | 5 |
| 19 | 常州市京锋工具有限公司的MIR Φ4车刀A60报价是多少？ | 微型车刀/镗刀 | MIR Φ4 A60 L15 | 43 | 20.87 | 51.47% | 1 | 0 |
| 20 | D4微型车刀，60°刀尖角，刃长15mm | 微型车刀/镗刀 | MIR Φ4 A60 L15 | 43 | 20.87 | 51.47% | 1 | 0 |

## 小径/DLC/英制 Top Error 覆盖

- DLC涂层单刃螺旋铣刀 / 3.175*3.175*12*38: target=13, predicted=37.95, error=191.92%, specialToolFactor=0.55
- 微小径深沟平刀/球刀 T型刀 / 0.5/R0.25"(2/3/4/6/8): target=24, predicted=3.22, error=86.58%, specialToolFactor=0.45
- DLC涂层单刃螺旋铣刀 / 3.175*1.2*3*38: target=13, predicted=2.95, error=77.31%, specialToolFactor=0.55
- 数控英制球刀 / 1/2*1-1/4*1/2*3*4F: target=180, predicted=315.39, error=75.22%, specialToolFactor=1

## 结论

第二轮相对第一轮有明确改善，主要来自完整 quoteAnchors 和特殊小径解析修正。

## 下一步参数建议

- 继续按 supplier/category 增补真实报价单锚点，减少同题派生锚点对评测稳定性的影响。
- 对台阶钻、铰刀、圆棒建立独立的锚点分组或专门 sizeScale，避免与普通铣刀共用长径比规则。
- 对仍高估的小径类样本，优先检查规格字段是否应使用刃径而非柄径，再微调 specialToolFactor。
