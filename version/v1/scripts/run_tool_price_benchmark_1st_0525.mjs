import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { createRequire } from "node:module"
import { fileURLToPath } from "node:url"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const v1Dir = path.resolve(__dirname, "..")
const projectRoot = path.resolve(v1Dir, "..", "..")
const frontendDir = path.join(v1Dir, "template_need_to_combine")
const benchmarkPath = path.join(v1Dir, "tool_quote_benchmark_v1.json")
const resultsDir = path.join(v1Dir, "results")
const outputStem = "1st_0525"
const summaryPath = path.join(resultsDir, `${outputStem}_summary.md`)
const detailPath = path.join(resultsDir, `${outputStem}_detail.json`)
const errorsPath = path.join(resultsDir, `${outputStem}_errors.csv`)
const groupMetricsPath = path.join(resultsDir, `${outputStem}_group_metrics.json`)

const requireFromFrontend = createRequire(path.join(frontendDir, "package.json"))
const typescript = requireFromFrontend("typescript")

function round(value, digits = 6) {
  if (!Number.isFinite(value)) return null
  return Number(value.toFixed(digits))
}

function roundMoney(value) {
  if (!Number.isFinite(value)) return null
  return Number(value.toFixed(2))
}

function asText(value) {
  if (value == null) return ""
  if (Array.isArray(value)) return value.filter((item) => item != null).join(" / ")
  if (typeof value === "object") return JSON.stringify(value, null, 0)
  return String(value)
}

function loadFormulaModule() {
  const formulaPath = path.join(frontendDir, "lib", "tool-price-formula-v2.ts")
  const source = fs.readFileSync(formulaPath, "utf8")
  const transpiled = typescript.transpileModule(source, {
    compilerOptions: {
      module: typescript.ModuleKind.CommonJS,
      target: typescript.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
    fileName: formulaPath,
  }).outputText

  const module = { exports: {} }
  const context = vm.createContext({
    module,
    exports: module.exports,
    require: requireFromFrontend,
    console,
  })
  new vm.Script(transpiled, { filename: formulaPath }).runInContext(context)
  return module.exports
}

function parseBenchmark() {
  const raw = fs.readFileSync(benchmarkPath, "utf8")
  const parsed = JSON.parse(raw)
  const questions = Array.isArray(parsed) ? parsed : parsed.questions
  if (!Array.isArray(questions)) {
    throw new Error("Benchmark file does not contain a questions array")
  }
  return { meta: parsed.meta ?? {}, questions }
}

function validPrice(value) {
  return Number.isFinite(value) && value > 0
}

function normalizeAnswerPrice(item) {
  const answerPrice = item.answer_price
  if (typeof answerPrice === "number") {
    if (!validPrice(answerPrice)) throw new Error("answer_price number is not a positive finite value")
    return {
      eval_target_price: answerPrice,
      eval_price_label: item.answer_price_str ?? String(answerPrice),
      price_pick_method: "number_direct",
    }
  }

  if (Array.isArray(answerPrice)) {
    const first = answerPrice.find((value) => validPrice(Number(value)))
    if (first == null) throw new Error("answer_price array has no positive numeric value")
    return {
      eval_target_price: Number(first),
      eval_price_label: item.answer_price_str ?? String(first),
      price_pick_method: "array_first",
      full_price_array: answerPrice,
    }
  }

  if (answerPrice && typeof answerPrice === "object") {
    const entries = Object.entries(answerPrice)
      .map(([key, value]) => ({ key, value: Number(value) }))
      .filter((entry) => validPrice(entry.value))
    if (!entries.length) throw new Error("answer_price object has no positive numeric value")

    const question = asText(item.question)
    const keywordRules = [
      "平刀",
      "球刀",
      "圆鼻刀",
      "不含税",
      "含税",
      "单价",
    ]
    for (const keyword of keywordRules) {
      if (!question.includes(keyword)) continue
      const match = entries.find((entry) => entry.key.includes(keyword))
      if (match) {
        return {
          eval_target_price: match.value,
          eval_price_label: `${match.key}: ${match.value}`,
          price_pick_method: "object_keyword_match",
        }
      }
    }

    const min = entries.slice().sort((a, b) => a.value - b.value)[0]
    return {
      eval_target_price: min.value,
      eval_price_label: `${min.key}: ${min.value}`,
      price_pick_method: "object_min_fallback",
    }
  }

  throw new Error(`unsupported answer_price type: ${typeof answerPrice}`)
}

function inferMaterial(category) {
  const text = asText(category).toUpperCase()
  if (text.includes("陶瓷")) return "CERAMIC"
  if (text.includes("PCD")) return "PCD"
  if (text.includes("CBN")) return "CBN"
  if (text.includes("高速钢") || text.includes("HSS")) return "HSS"
  return "CARBIDE"
}

function inferProcessFactor(category) {
  const text = asText(category)
  if (["铣刀", "球刀", "圆鼻刀", "粗皮刀", "U槽刀"].some((keyword) => text.includes(keyword))) return 1.18
  if (text.includes("台阶钻") || text.includes("钻")) return 1.1
  if (text.includes("铰刀")) return 1.18
  if (["车刀", "镗刀", "刀片", "圆棒"].some((keyword) => text.includes(keyword))) return 1
  return 1
}

function inferWorkpieceFactor(item) {
  const text = `${asText(item.question)} ${asText(item.answer_category)} ${asText(item.answer_spec)} ${asText(item.spec_raw)}`
  if (["钛合金", "高温合金"].some((keyword) => text.includes(keyword))) return 1.35
  if (text.includes("不锈钢")) return 1.12
  if (["铝合金", "铝", "6系", "7系"].some((keyword) => text.includes(keyword))) return 0.95
  if (["钢件", "模具钢"].some((keyword) => text.includes(keyword))) return 1
  return 1
}

function buildSpec(item, formula) {
  const category = asText(item.answer_category)
  const rawSpec = asText(item.answer_spec || item.spec_raw)
  const parsed = formula.parseToolSpec(rawSpec, category)
  const textForPrecision = `${category} ${rawSpec}`.toUpperCase()
  return {
    supplier: asText(item.answer_supplier),
    category,
    rawSpec,
    toolKind: formula.inferToolKind(category, rawSpec),
    coating: formula.inferCoating(category),
    material: inferMaterial(category),
    precision: textForPrecision.includes("H7") ? 80 : 50,
    parsed,
    spec: {
      supplier: asText(item.answer_supplier),
      category,
      rawSpec,
      toolKind: formula.inferToolKind(category, rawSpec),
      coating: formula.inferCoating(category),
      material: inferMaterial(category),
      taxMode: asText(item.question).includes("不含税")
        ? "TAX_EXCLUDED"
        : asText(item.question).includes("含税")
          ? "TAX_INCLUDED"
          : "UNKNOWN",
      ...parsed,
    },
  }
}

function normalizeSupplierForCompare(supplier) {
  return asText(supplier).replace(/^benchmark:/, "")
}

function isSameAnchor(anchor, item, targetPrice) {
  return (
    normalizeSupplierForCompare(anchor.supplier) === normalizeSupplierForCompare(item.answer_supplier) &&
    asText(anchor.category) === asText(item.answer_category) &&
    asText(anchor.rawSpec) === asText(item.answer_spec || item.spec_raw) &&
    Math.abs(Number(anchor.price) - Number(targetPrice)) < 1e-9
  )
}

function loadQuoteAnchors(formula, questions) {
  const anchorsPath = path.join(frontendDir, "data", "quote-anchors.json")
  if (fs.existsSync(anchorsPath)) {
    const rawAnchors = JSON.parse(fs.readFileSync(anchorsPath, "utf8"))
    const anchors = formula.normalizeQuoteAnchors(rawAnchors)
    if (anchors.length > 0) {
      return { anchors, source: anchorsPath, generatedFromBenchmark: false }
    }
  }

  const rawAnchors = []
  for (const item of questions) {
    try {
      const normalized = normalizeAnswerPrice(item)
      const built = buildSpec(item, formula)
      rawAnchors.push({
        question: item.question,
        supplier: built.spec.supplier,
        category: built.spec.category,
        rawSpec: built.spec.rawSpec,
        price: normalized.eval_target_price,
        priceLabel: normalized.eval_price_label,
        toolKind: built.spec.toolKind,
        coating: built.spec.coating,
        material: built.spec.material,
        diameterMm: built.parsed.diameterMm,
        fluteLengthMm: built.parsed.fluteLengthMm,
        totalLengthMm: built.parsed.totalLengthMm,
        shankDiameterMm: built.parsed.shankDiameterMm,
        fluteCount: built.parsed.fluteCount,
        radiusMm: built.parsed.radiusMm,
        tolerance: built.parsed.tolerance,
      })
    } catch {
      // Non-price benchmark rows are intentionally left out of temporary anchors.
    }
  }
  return { anchors: rawAnchors.filter((anchor) => validPrice(anchor.price)), source: "benchmark_generated", generatedFromBenchmark: true }
}

async function tryLoadMarketFactor() {
  const url = "http://127.0.0.1:8765/api/market/production-forecasts?horizon_day=30"
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 2500)
  try {
    const response = await fetch(url, { signal: controller.signal })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const payload = await response.json()
    const rows = Array.isArray(payload) ? payload : Array.isArray(payload.items) ? payload.items : Array.isArray(payload.data) ? payload.data : []
    const returns = rows
      .map((row) => {
        for (const key of ["final_predicted_return", "predicted_return", "forecast_return", "expected_return", "return_pct", "predicted_return_30d"]) {
          const value = Number(row?.[key])
          if (Number.isFinite(value)) return Math.abs(value) > 1 ? value / 100 : value
        }
        const base = Number(row?.base_price ?? row?.current_price)
        const future = Number(row?.final_predicted_price ?? row?.predicted_price ?? row?.forecast_price)
        if (validPrice(base) && validPrice(future)) return future / base - 1
        return null
      })
      .filter((value) => Number.isFinite(value))
    if (!returns.length) throw new Error("no usable 30d return fields in API response")
    const avgReturn = returns.reduce((sum, value) => sum + value, 0) / returns.length
    const mFuture = Math.max(0.85, Math.min(1.15, 1 + avgReturn))
    return {
      marketApiConnected: true,
      marketApiUrl: url,
      mFuture,
      rG: 1,
      rQ: 1,
      note: `接入本机 production-forecasts，使用 ${returns.length} 条 30 天预测的平均收益率计算 mFuture。`,
    }
  } catch (error) {
    return {
      marketApiConnected: false,
      marketApiUrl: url,
      mFuture: 1,
      rG: 1,
      rQ: 1,
      note: `本次 benchmark 未接入实时行情 API，使用 mFuture=1.0，仅评估规格报价逻辑。API 尝试失败：${error.message}`,
    }
  } finally {
    clearTimeout(timeout)
  }
}

function diameterBucket(diameter) {
  if (!Number.isFinite(diameter)) return "unknown"
  if (diameter <= 4) return "D <= 4"
  if (diameter <= 6) return "4 < D <= 6"
  if (diameter <= 8) return "6 < D <= 8"
  if (diameter <= 10) return "8 < D <= 10"
  if (diameter <= 12) return "10 < D <= 12"
  return "D > 12"
}

function median(values) {
  const sorted = values.filter(Number.isFinite).slice().sort((a, b) => a - b)
  if (!sorted.length) return null
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

function metricsFor(rows) {
  const evaluated = rows.filter((row) => !row.skipped_reason && validPrice(row.eval_target_price) && Number.isFinite(row.predictedPrice))
  const count = evaluated.length
  if (!count) {
    return {
      count: 0,
      MAPE: null,
      MdAPE: null,
      RMSE: null,
      MAE: null,
      mean_signed_percentage_error: null,
      within_10pct_rate: null,
      within_20pct_rate: null,
      within_30pct_rate: null,
      interval_hit_rate: null,
      overestimate_rate: null,
      underestimate_rate: null,
    }
  }
  const absPct = evaluated.map((row) => row.percentage_error)
  const signedPct = evaluated.map((row) => row.signed_percentage_error)
  const absErr = evaluated.map((row) => row.absolute_error)
  return {
    count,
    MAPE: round(absPct.reduce((sum, value) => sum + value, 0) / count),
    MdAPE: round(median(absPct)),
    RMSE: round(Math.sqrt(absErr.reduce((sum, value) => sum + value * value, 0) / count), 4),
    MAE: round(absErr.reduce((sum, value) => sum + value, 0) / count, 4),
    mean_signed_percentage_error: round(signedPct.reduce((sum, value) => sum + value, 0) / count),
    within_10pct_rate: round(evaluated.filter((row) => row.within_10pct).length / count),
    within_20pct_rate: round(evaluated.filter((row) => row.within_20pct).length / count),
    within_30pct_rate: round(evaluated.filter((row) => row.within_30pct).length / count),
    interval_hit_rate: round(evaluated.filter((row) => row.interval_hit).length / count),
    overestimate_rate: round(evaluated.filter((row) => row.signed_percentage_error > 0).length / count),
    underestimate_rate: round(evaluated.filter((row) => row.signed_percentage_error < 0).length / count),
  }
}

function groupBy(rows, keyGetter) {
  const groups = {}
  for (const row of rows) {
    const key = keyGetter(row) || "unknown"
    groups[key] ??= []
    groups[key].push(row)
  }
  return Object.fromEntries(
    Object.entries(groups)
      .sort(([a], [b]) => a.localeCompare(b, "zh-Hans-CN"))
      .map(([key, groupRows]) => [key, slimGroupMetrics(groupRows)]),
  )
}

function slimGroupMetrics(rows) {
  const full = metricsFor(rows)
  return {
    count: full.count,
    MAPE: full.MAPE,
    MdAPE: full.MdAPE,
    within_30pct_rate: full.within_30pct_rate,
    interval_hit_rate: full.interval_hit_rate,
    mean_signed_percentage_error: full.mean_signed_percentage_error,
  }
}

function csvCell(value) {
  const text = value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value)
  return `"${text.replace(/"/g, '""').replace(/\r?\n/g, " ")}"`
}

function percent(value) {
  return value == null ? "N/A" : `${(value * 100).toFixed(2)}%`
}

function metricTable(metrics) {
  return [
    "| metric | value |",
    "| --- | ---: |",
    `| total_questions | ${metrics.total_questions} |`,
    `| evaluated_questions | ${metrics.evaluated_questions} |`,
    `| skipped_questions | ${metrics.skipped_questions} |`,
    `| MAPE | ${percent(metrics.MAPE)} |`,
    `| MdAPE | ${percent(metrics.MdAPE)} |`,
    `| RMSE | ${metrics.RMSE ?? "N/A"} |`,
    `| MAE | ${metrics.MAE ?? "N/A"} |`,
    `| mean_signed_percentage_error | ${percent(metrics.mean_signed_percentage_error)} |`,
    `| within_10pct_rate | ${percent(metrics.within_10pct_rate)} |`,
    `| within_20pct_rate | ${percent(metrics.within_20pct_rate)} |`,
    `| within_30pct_rate | ${percent(metrics.within_30pct_rate)} |`,
    `| interval_hit_rate | ${percent(metrics.interval_hit_rate)} |`,
    `| overestimate_rate | ${percent(metrics.overestimate_rate)} |`,
    `| underestimate_rate | ${percent(metrics.underestimate_rate)} |`,
  ].join("\n")
}

function groupTable(groupMetrics) {
  const rows = Object.entries(groupMetrics).map(([name, metrics]) => {
    return `| ${name.replace(/\|/g, "/")} | ${metrics.count} | ${percent(metrics.MAPE)} | ${percent(metrics.MdAPE)} | ${percent(metrics.within_30pct_rate)} | ${percent(metrics.interval_hit_rate)} | ${percent(metrics.mean_signed_percentage_error)} |`
  })
  return ["| group | count | MAPE | MdAPE | within_30pct | interval_hit | mean_signed_pct_error |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |", ...rows].join("\n")
}

function buildSummary({ runAt, market, anchorInfo, overallMetrics, groupMetrics, details }) {
  const evaluated = details.filter((row) => !row.skipped_reason)
  const topErrors = evaluated
    .slice()
    .sort((a, b) => b.percentage_error - a.percentage_error)
    .slice(0, 20)
    .map((row, index) => `| ${index + 1} | ${row.question.replace(/\|/g, "/")} | ${row.supplier.replace(/\|/g, "/")} | ${row.category.replace(/\|/g, "/")} | ${row.rawSpec.replace(/\|/g, "/")} | ${row.eval_target_price} | ${row.predictedPrice} | ${percent(row.percentage_error)} | ${percent(row.signed_percentage_error)} |`)

  const categorySigned = Object.entries(groupMetrics.by_category)
    .map(([category, metrics]) => ({ category, ...metrics }))
    .filter((item) => item.count > 0 && item.mean_signed_percentage_error != null)
  const high = categorySigned
    .filter((item) => item.mean_signed_percentage_error > 0)
    .sort((a, b) => b.mean_signed_percentage_error - a.mean_signed_percentage_error)
    .slice(0, 10)
  const low = categorySigned
    .filter((item) => item.mean_signed_percentage_error < 0)
    .sort((a, b) => a.mean_signed_percentage_error - b.mean_signed_percentage_error)
    .slice(0, 10)

  const reached = overallMetrics.within_30pct_rate != null && overallMetrics.within_30pct_rate >= 0.8 && overallMetrics.MAPE != null && overallMetrics.MAPE <= 0.3
  const nextSteps = []
  if (overallMetrics.mean_signed_percentage_error > 0.1) nextSteps.push("整体存在高估，需要下调 fProcess、toolKindFactor 或锚点外推系数。")
  if (overallMetrics.mean_signed_percentage_error < -0.1) nextSteps.push("整体存在低估，需要上调 fallbackRefPrice、材质/涂层系数或补充高价锚点。")
  if ((overallMetrics.within_30pct_rate ?? 0) < 0.8) nextSteps.push("±30% 命中率不足，优先扩充 quoteAnchors，并按品类校准 sizeScale 指数。")
  if ((overallMetrics.interval_hit_rate ?? 0) < 0.8) nextSteps.push("区间命中率不足，低相似度场景的 intervalRate 需要扩大或改为按品类动态估计。")
  if (!nextSteps.length) nextSteps.push("当前主指标接近目标，下一步应使用更多非泄漏锚点做稳定性复核。")

  return [
    "# Tool Price Formula V2 Benchmark - 1st_0525",
    "",
    `- 本次评测时间：${runAt}`,
    `- benchmark 文件路径：${benchmarkPath}`,
    "- formulaVersion：tool_price_formula_v2",
    `- 是否接入行情 API：${market.marketApiConnected ? "是" : "否"}`,
    `- 行情说明：${market.note}`,
    `- quoteAnchors 来源：${anchorInfo.source}`,
    `- quoteAnchors 数量：${anchorInfo.anchors.length}`,
    "",
    "## 总体指标",
    "",
    metricTable(overallMetrics),
    "",
    "## 分 level 指标",
    "",
    groupTable(groupMetrics.by_level),
    "",
    "## 分 type 指标",
    "",
    groupTable(groupMetrics.by_type),
    "",
    "## Top 20 误差最大样本",
    "",
    ["| rank | question | supplier | category | rawSpec | target | predicted | abs_pct_error | signed_pct_error |", "| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: |", ...topErrors].join("\n"),
    "",
    "## Top 10 系统性高估品类",
    "",
    ["| rank | category | count | mean_signed_percentage_error | MAPE | within_30pct |", "| ---: | --- | ---: | ---: | ---: | ---: |", ...high.map((item, index) => `| ${index + 1} | ${item.category.replace(/\|/g, "/")} | ${item.count} | ${percent(item.mean_signed_percentage_error)} | ${percent(item.MAPE)} | ${percent(item.within_30pct_rate)} |`)].join("\n"),
    "",
    "## Top 10 系统性低估品类",
    "",
    ["| rank | category | count | mean_signed_percentage_error | MAPE | within_30pct |", "| ---: | --- | ---: | ---: | ---: | ---: |", ...low.map((item, index) => `| ${index + 1} | ${item.category.replace(/\|/g, "/")} | ${item.count} | ${percent(item.mean_signed_percentage_error)} | ${percent(item.MAPE)} | ${percent(item.within_30pct_rate)} |`)].join("\n"),
    "",
    "## 结论",
    "",
    reached
      ? `当前公式在本次 benchmark 上达到 ±30% 目标：within_30pct_rate=${percent(overallMetrics.within_30pct_rate)}，MAPE=${percent(overallMetrics.MAPE)}。`
      : `当前公式在本次 benchmark 上尚未达到稳定 ±30% 目标：within_30pct_rate=${percent(overallMetrics.within_30pct_rate)}，MAPE=${percent(overallMetrics.MAPE)}。`,
    "",
    "## 下一步需要校准的参数建议",
    "",
    ...nextSteps.map((item) => `- ${item}`),
    "",
  ].join("\n")
}

async function main() {
  fs.mkdirSync(resultsDir, { recursive: true })
  const runAt = new Date().toISOString()
  const formula = loadFormulaModule()
  const { meta, questions } = parseBenchmark()
  const anchorInfo = loadQuoteAnchors(formula, questions)
  const market = await tryLoadMarketFactor()

  const details = []
  const errorRows = []

  for (const [index, item] of questions.entries()) {
    const base = {
      index: index + 1,
      question: asText(item.question),
      level: item.level ?? null,
      type: item.type ?? null,
      supplier: asText(item.answer_supplier),
      category: asText(item.answer_category),
      rawSpec: asText(item.answer_spec || item.spec_raw),
      answer_price: item.answer_price ?? null,
      skipped_reason: null,
    }
    try {
      const normalized = normalizeAnswerPrice(item)
      const built = buildSpec(item, formula)
      const quoteAnchors = anchorInfo.anchors.filter((anchor) => !isSameAnchor(anchor, item, normalized.eval_target_price))
      const result = formula.calculateToolPriceV2({
        spec: built.spec,
        quoteAnchors,
        fIndustry: 1,
        fProcess: inferProcessFactor(built.spec.category),
        fWorkpiece: inferWorkpieceFactor(item),
        mFuture: market.mFuture,
        precision: built.precision,
      })

      const predictedPrice = result.predictedPrice
      const target = normalized.eval_target_price
      const absoluteError = Math.abs(predictedPrice - target)
      const percentageError = absoluteError / target
      const signedPercentageError = (predictedPrice - target) / target

      details.push({
        ...base,
        supplier: built.spec.supplier,
        category: built.spec.category,
        rawSpec: built.spec.rawSpec,
        toolKind: built.spec.toolKind,
        coating: built.spec.coating,
        material: built.spec.material,
        diameterMm: built.parsed.diameterMm ?? null,
        diameter_bucket: diameterBucket(built.parsed.diameterMm),
        eval_target_price: roundMoney(target),
        eval_price_label: normalized.eval_price_label,
        price_pick_method: normalized.price_pick_method,
        full_price_array: normalized.full_price_array ?? undefined,
        predictedPrice,
        lowerPrice: result.lowerPrice,
        upperPrice: result.upperPrice,
        intervalRate: result.intervalRate,
        absolute_error: roundMoney(absoluteError),
        percentage_error: round(percentageError),
        signed_percentage_error: round(signedPercentageError),
        within_10pct: percentageError <= 0.1,
        within_20pct: percentageError <= 0.2,
        within_30pct: percentageError <= 0.3,
        interval_hit: target >= result.lowerPrice && target <= result.upperPrice,
        formulaVersion: result.formulaVersion,
        matchedAnchors: result.matchedAnchors,
        specBasePrice: result.specBasePrice,
        fIndustry: 1,
        fProcess: inferProcessFactor(built.spec.category),
        fWorkpiece: inferWorkpieceFactor(item),
        mFuture: market.mFuture,
        rG: market.rG,
        rQ: market.rQ,
        quoteAnchorCountUsed: quoteAnchors.length,
      })
    } catch (error) {
      const skippedReason = `skipped_price_parse_failed: ${error.message}`
      details.push({
        ...base,
        diameter_bucket: "unknown",
        eval_target_price: null,
        eval_price_label: null,
        price_pick_method: null,
        predictedPrice: null,
        lowerPrice: null,
        upperPrice: null,
        intervalRate: null,
        absolute_error: null,
        percentage_error: null,
        signed_percentage_error: null,
        within_10pct: null,
        within_20pct: null,
        within_30pct: null,
        interval_hit: null,
        formulaVersion: "tool_price_formula_v2",
        matchedAnchors: [],
        specBasePrice: null,
        skipped_reason: skippedReason,
      })
      errorRows.push({
        question: base.question,
        supplier: base.supplier,
        category: base.category,
        rawSpec: base.rawSpec,
        answer_price: item.answer_price ?? null,
        error_reason: skippedReason,
      })
    }
  }

  const evaluatedQuestions = details.filter((row) => !row.skipped_reason).length
  const overallCore = metricsFor(details)
  const overallMetrics = {
    total_questions: questions.length,
    evaluated_questions: evaluatedQuestions,
    skipped_questions: questions.length - evaluatedQuestions,
    MAPE: overallCore.MAPE,
    MdAPE: overallCore.MdAPE,
    RMSE: overallCore.RMSE,
    MAE: overallCore.MAE,
    mean_signed_percentage_error: overallCore.mean_signed_percentage_error,
    within_10pct_rate: overallCore.within_10pct_rate,
    within_20pct_rate: overallCore.within_20pct_rate,
    within_30pct_rate: overallCore.within_30pct_rate,
    interval_hit_rate: overallCore.interval_hit_rate,
    overestimate_rate: overallCore.overestimate_rate,
    underestimate_rate: overallCore.underestimate_rate,
  }

  const groupMetrics = {
    by_supplier: groupBy(details, (row) => row.supplier),
    by_category: groupBy(details, (row) => row.category),
    by_level: groupBy(details, (row) => String(row.level ?? "unknown")),
    by_type: groupBy(details, (row) => String(row.type ?? "unknown")),
    by_diameter_bucket: groupBy(details, (row) => row.diameter_bucket),
  }

  const detailOutput = {
    meta,
    runAt,
    benchmarkPath,
    formulaVersion: "tool_price_formula_v2",
    market,
    quoteAnchors: {
      source: anchorInfo.source,
      count: anchorInfo.anchors.length,
      generatedFromBenchmark: anchorInfo.generatedFromBenchmark,
    },
    overallMetrics,
    details,
  }

  fs.writeFileSync(detailPath, JSON.stringify(detailOutput, null, 2), "utf8")
  fs.writeFileSync(groupMetricsPath, JSON.stringify(groupMetrics, null, 2), "utf8")
  fs.writeFileSync(
    errorsPath,
    [
      ["question", "supplier", "category", "rawSpec", "answer_price", "error_reason"].map(csvCell).join(","),
      ...errorRows.map((row) => [row.question, row.supplier, row.category, row.rawSpec, row.answer_price, row.error_reason].map(csvCell).join(",")),
    ].join("\n"),
    "utf8",
  )
  fs.writeFileSync(summaryPath, buildSummary({ runAt, market, anchorInfo, overallMetrics, groupMetrics, details }), "utf8")

  console.log("Tool price formula v2 benchmark completed.")
  console.log(`Run name: ${outputStem}`)
  console.log(`Benchmark: ${benchmarkPath}`)
  console.log(`Formula: tool_price_formula_v2`)
  console.log(`Market API connected: ${market.marketApiConnected}`)
  console.log(`Quote anchors: ${anchorInfo.anchors.length} (${anchorInfo.source})`)
  console.log(`Total questions: ${overallMetrics.total_questions}`)
  console.log(`Evaluated questions: ${overallMetrics.evaluated_questions}`)
  console.log(`Skipped questions: ${overallMetrics.skipped_questions}`)
  console.log(`MAPE: ${percent(overallMetrics.MAPE)}`)
  console.log(`MdAPE: ${percent(overallMetrics.MdAPE)}`)
  console.log(`RMSE: ${overallMetrics.RMSE}`)
  console.log(`MAE: ${overallMetrics.MAE}`)
  console.log(`Mean signed pct error: ${percent(overallMetrics.mean_signed_percentage_error)}`)
  console.log(`Within 30 pct rate: ${percent(overallMetrics.within_30pct_rate)}`)
  console.log(`Interval hit rate: ${percent(overallMetrics.interval_hit_rate)}`)
  console.log(`Summary: ${summaryPath}`)
  console.log(`Detail: ${detailPath}`)
  console.log(`Errors: ${errorsPath}`)
  console.log(`Group metrics: ${groupMetricsPath}`)
}

main().catch((error) => {
  console.error("Benchmark failed:", error)
  process.exitCode = 1
})
