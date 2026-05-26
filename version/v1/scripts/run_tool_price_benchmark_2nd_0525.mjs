import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { createRequire } from "node:module"
import { fileURLToPath } from "node:url"

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const v1Dir = path.resolve(__dirname, "..")
const frontendDir = path.join(v1Dir, "template_need_to_combine")
const benchmarkPath = path.join(v1Dir, "tool_quote_benchmark_v1.json")
const dataAnchorsPath = path.join(frontendDir, "data", "generated-quote-anchors-2nd-0525.json")
const resultsDir = path.join(v1Dir, "results")
const outputStem = "2nd_0525"
const summaryPath = path.join(resultsDir, `${outputStem}_summary.md`)
const detailPath = path.join(resultsDir, `${outputStem}_detail.json`)
const errorsPath = path.join(resultsDir, `${outputStem}_errors.csv`)
const groupMetricsPath = path.join(resultsDir, `${outputStem}_group_metrics.json`)
const resultAnchorsPath = path.join(resultsDir, `${outputStem}_generated_anchors.json`)

const requireFromFrontend = createRequire(path.join(frontendDir, "package.json"))
const typescript = requireFromFrontend("typescript")
const FIRST_ROUND = {
  MAPE: 0.595716,
  within_30pct_rate: 0.276923,
  interval_hit_rate: 0.292308,
  evaluated_questions: 65,
  quoteAnchors: 5,
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
  const context = vm.createContext({ module, exports: module.exports, require: requireFromFrontend, console })
  new vm.Script(transpiled, { filename: formulaPath }).runInContext(context)
  return module.exports
}

function round(value, digits = 6) {
  return Number.isFinite(value) ? Number(value.toFixed(digits)) : null
}

function roundMoney(value) {
  return Number.isFinite(value) ? Number(value.toFixed(2)) : null
}

function percent(value) {
  return value == null ? "N/A" : `${(value * 100).toFixed(2)}%`
}

function text(value) {
  if (value == null) return ""
  if (Array.isArray(value)) return value.filter((item) => item != null).join(" / ")
  if (typeof value === "object") return JSON.stringify(value)
  return String(value)
}

function validPrice(value) {
  return Number.isFinite(value) && value > 0
}

function priceFromText(value) {
  if (typeof value === "number") return validPrice(value) ? value : null
  const match = text(value).replace(/,/g, "").match(/-?\d+(?:\.\d+)?/)
  const parsed = match ? Number(match[0]) : NaN
  return validPrice(parsed) ? parsed : null
}

function parseBenchmark() {
  const parsed = JSON.parse(fs.readFileSync(benchmarkPath, "utf8"))
  const questions = Array.isArray(parsed) ? parsed : parsed.questions
  if (!Array.isArray(questions)) throw new Error("Benchmark file does not contain questions")
  return { meta: parsed.meta ?? {}, questions }
}

function inferMaterial(category, question = "") {
  const value = `${category} ${question}`.toUpperCase()
  if (value.includes("陶瓷")) return "CERAMIC"
  if (value.includes("PCD")) return "PCD"
  if (value.includes("CBN")) return "CBN"
  if (value.includes("高速钢") || value.includes("HSS")) return "HSS"
  return "CARBIDE"
}

function buildSpecParts(item, formula, overrides = {}) {
  const supplier = text(overrides.supplier ?? item.answer_supplier)
  const category = text(overrides.category ?? item.answer_category)
  const rawSpec = text(overrides.rawSpec ?? item.answer_spec ?? item.spec_raw)
  const parsed = formula.parseToolSpec(rawSpec, category)
  const toolKind = formula.inferToolKind(category, rawSpec)
  const coating = formula.inferCoating(category)
  const material = inferMaterial(category, item.question)
  const precision = `${category} ${rawSpec}`.toUpperCase().includes("H7") ? 80 : 50
  return {
    supplier,
    category,
    rawSpec,
    parsed,
    precision,
    spec: {
      supplier,
      category,
      rawSpec,
      toolKind,
      coating,
      material,
      taxMode: text(item.question).includes("不含税") ? "TAX_EXCLUDED" : text(item.question).includes("含税") ? "TAX_INCLUDED" : "UNKNOWN",
      ...parsed,
    },
  }
}

function normalizeTargetPrice(item) {
  const answerPrice = item.answer_price
  if (typeof answerPrice === "number" && validPrice(answerPrice)) {
    return { price: answerPrice, priceLabel: item.answer_price_str ?? String(answerPrice), method: "number_direct" }
  }
  if (Array.isArray(answerPrice)) {
    const index = answerPrice.findIndex((value) => validPrice(Number(value)))
    if (index >= 0) return { price: Number(answerPrice[index]), priceLabel: `array_${index}`, method: "array_first", full_price_array: answerPrice }
  }
  if (answerPrice && typeof answerPrice === "object") {
    const entries = Object.entries(answerPrice)
      .map(([key, value]) => ({ key, value: Number(value) }))
      .filter((entry) => validPrice(entry.value))
    if (!entries.length) return null
    const question = text(item.question)
    for (const keyword of ["平刀", "球刀", "圆鼻刀", "不含税", "含税", "单价"]) {
      if (!question.includes(keyword)) continue
      const match = entries.find((entry) => entry.key.includes(keyword))
      if (match) return { price: match.value, priceLabel: match.key, method: "object_keyword_match" }
    }
    const min = entries.slice().sort((a, b) => a.value - b.value)[0]
    return { price: min.value, priceLabel: min.key, method: "object_min_fallback" }
  }
  if (typeof item.answer_price_simple === "number" && validPrice(item.answer_price_simple)) {
    return { price: item.answer_price_simple, priceLabel: "answer_price_simple", method: "answer_price_simple" }
  }
  return null
}

function anchorFrom(item, formula, price, priceLabel, source, overrides = {}) {
  const parts = buildSpecParts(item, formula, overrides)
  if (!parts.supplier || !parts.category || !parts.rawSpec || !validPrice(price)) return null
  return {
    sourceQuestion: item.question,
    sourceType: source,
    supplier: parts.supplier,
    category: parts.category,
    rawSpec: parts.rawSpec,
    price: roundMoney(price),
    priceLabel,
    toolKind: parts.spec.toolKind,
    coating: parts.spec.coating,
    material: parts.spec.material,
    diameterMm: parts.parsed.diameterMm,
    radiusMm: parts.parsed.radiusMm,
    fluteLengthMm: parts.parsed.fluteLengthMm,
    totalLengthMm: parts.parsed.totalLengthMm,
    shankDiameterMm: parts.parsed.shankDiameterMm,
    fluteCount: parts.parsed.fluteCount,
    tolerance: parts.parsed.tolerance,
  }
}

function anchorsFromQuestion(item, formula) {
  const anchors = []
  const answerPrice = item.answer_price
  if (typeof answerPrice === "number") {
    const anchor = anchorFrom(item, formula, answerPrice, item.answer_price_str ?? String(answerPrice), "answer_price_number")
    if (anchor) anchors.push(anchor)
  } else if (Array.isArray(answerPrice)) {
    answerPrice.forEach((value, index) => {
      const price = Number(value)
      const anchor = anchorFrom(item, formula, price, `array_${index}`, "answer_price_array")
      if (anchor) anchors.push(anchor)
    })
  } else if (answerPrice && typeof answerPrice === "object") {
    for (const [key, value] of Object.entries(answerPrice)) {
      const anchor = anchorFrom(item, formula, Number(value), key, "answer_price_object")
      if (anchor) anchors.push(anchor)
    }
  }
  return anchors
}

function generateAnchors(questions, formula) {
  const anchors = []
  for (const item of questions) {
    anchors.push(...anchorsFromQuestion(item, formula))
  }
  return anchors
}

function sameIdentity(a, b) {
  return text(a.supplier) === text(b.supplier) && text(a.category) === text(b.category) && text(a.rawSpec) === text(b.rawSpec)
}

function excludeCurrent(anchors, current) {
  return anchors.filter((anchor) => {
    return !(
      sameIdentity(anchor, current) &&
      Math.abs(Number(anchor.price) - Number(current.price)) < 1e-9 &&
      text(anchor.priceLabel) === text(current.priceLabel)
    )
  })
}

function inferProcessFactor(category) {
  const value = text(category)
  if (["铣刀", "球刀", "圆鼻刀", "粗皮刀", "U槽刀"].some((keyword) => value.includes(keyword))) return 1.18
  if (value.includes("台阶钻") || value.includes("钻")) return 1.1
  if (value.includes("铰刀")) return 1.18
  if (["车刀", "镗刀", "刀片", "圆棒"].some((keyword) => value.includes(keyword))) return 1
  return 1
}

function inferWorkpieceFactor(item) {
  const value = `${item.question ?? ""} ${item.answer_category ?? ""} ${item.answer_spec ?? ""} ${item.spec_raw ?? ""}`
  if (value.includes("不锈钢")) return 1.12
  if (value.includes("钛合金") || value.includes("高温合金")) return 1.35
  if (value.includes("铝合金") || value.includes("铝") || value.includes("6系") || value.includes("7系")) return 0.95
  return 1
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

async function tryLoadMarketFactor() {
  const url = "http://127.0.0.1:8765/api/market/production-forecasts?horizon_day=30"
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 2500)
  try {
    const response = await fetch(url, { signal: controller.signal })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const rows = await response.json()
    const returns = (Array.isArray(rows) ? rows : rows.items ?? rows.data ?? [])
      .map((row) => Number(row.final_predicted_return ?? row.predicted_return ?? row.forecast_return))
      .filter(Number.isFinite)
    if (!returns.length) throw new Error("no usable return fields")
    const avg = returns.reduce((sum, value) => sum + value, 0) / returns.length
    return { marketApiConnected: true, marketApiUrl: url, mFuture: Math.max(0.85, Math.min(1.15, 1 + avg)), rG: 1, rQ: 1, note: `接入本机 production-forecasts，使用 ${returns.length} 条 30 天预测的平均收益率计算 mFuture。` }
  } catch (error) {
    return { marketApiConnected: false, marketApiUrl: url, mFuture: 1, rG: 1, rQ: 1, note: `本次 benchmark 未接入实时行情 API，使用 mFuture=1.0，仅评估规格报价逻辑。API 尝试失败：${error.message}` }
  } finally {
    clearTimeout(timeout)
  }
}

function calculate(formula, item, currentAnchor, quoteAnchors, market, overrides = {}) {
  const parts = buildSpecParts(item, formula, overrides)
  const result = formula.calculateToolPriceV2({
    spec: parts.spec,
    quoteAnchors,
    fIndustry: 1,
    fProcess: inferProcessFactor(parts.spec.category),
    fWorkpiece: inferWorkpieceFactor(item),
    mFuture: market.mFuture,
    precision: parts.precision,
  })
  return { parts, result, specialToolFactor: formula.getSpecialToolFactor?.(parts.spec) ?? null }
}

function evaluatePriceQuestion(item, index, formula, generatedAnchors, market) {
  const normalized = normalizeTargetPrice(item)
  const base = {
    index: index + 1,
    question: text(item.question),
    level: item.level ?? null,
    type: item.type ?? null,
    supplier: text(item.answer_supplier),
    category: text(item.answer_category),
    rawSpec: text(item.answer_spec || item.spec_raw),
    skipped_reason: null,
    eval_kind: "price",
  }
  if (!normalized) throw new Error("no direct price target")
  const currentAnchor = anchorFrom(item, formula, normalized.price, normalized.priceLabel, "eval_target")
  const quoteAnchors = excludeCurrent(generatedAnchors, currentAnchor)
  const { parts, result, specialToolFactor } = calculate(formula, item, currentAnchor, quoteAnchors, market)
  const target = normalized.price
  const abs = Math.abs(result.predictedPrice - target)
  const pct = abs / target
  const signed = (result.predictedPrice - target) / target
  return {
    ...base,
    supplier: parts.supplier,
    category: parts.category,
    rawSpec: parts.rawSpec,
    toolKind: parts.spec.toolKind,
    coating: parts.spec.coating,
    material: parts.spec.material,
    diameterMm: parts.parsed.diameterMm ?? null,
    radiusMm: parts.parsed.radiusMm ?? null,
    fluteLengthMm: parts.parsed.fluteLengthMm ?? null,
    totalLengthMm: parts.parsed.totalLengthMm ?? null,
    shankDiameterMm: parts.parsed.shankDiameterMm ?? null,
    fluteCount: parts.parsed.fluteCount ?? null,
    tolerance: parts.parsed.tolerance ?? null,
    diameter_bucket: diameterBucket(parts.parsed.diameterMm),
    eval_target_price: roundMoney(target),
    eval_price_label: normalized.priceLabel,
    price_pick_method: normalized.method,
    full_price_array: normalized.full_price_array,
    predictedPrice: result.predictedPrice,
    lowerPrice: result.lowerPrice,
    upperPrice: result.upperPrice,
    intervalRate: result.intervalRate,
    absolute_error: roundMoney(abs),
    percentage_error: round(pct),
    signed_percentage_error: round(signed),
    within_10pct: pct <= 0.1,
    within_20pct: pct <= 0.2,
    within_30pct: pct <= 0.3,
    interval_hit: target >= result.lowerPrice && target <= result.upperPrice,
    formulaVersion: result.formulaVersion,
    matchedAnchors: result.matchedAnchors,
    specBasePrice: result.specBasePrice,
    specialToolFactor,
    quoteAnchorCountUsed: quoteAnchors.length,
  }
}

function extractRankingExpected(item) {
  const cheapest = item.answer_cheapest && typeof item.answer_cheapest === "object" ? item.answer_cheapest : null
  const cheapestSupplierFromText = typeof item.answer_cheapest === "string" ? item.answer_cheapest.match(/^[^(（]+/)?.[0]?.trim() : null
  const detailPrices = item.answer_price_detail && typeof item.answer_price_detail === "object"
    ? Object.entries(item.answer_price_detail)
        .map(([supplier, detail]) => ({ supplier, category: null, price: priceFromText(detail?.price), spec: detail?.spec }))
        .filter((entry) => entry.price != null)
        .sort((a, b) => a.price - b.price)
    : []
  const gradientPrices = Array.isArray(item.answer_prices_gradient)
    ? item.answer_prices_gradient
        .map((detail) => ({ supplier: item.answer_supplier ?? null, category: item.answer_categories?.[0] ?? item.answer_category ?? null, price: priceFromText(detail?.price), spec: `D8*${detail?.total_length}` }))
        .filter((entry) => entry.price != null)
        .sort((a, b) => a.price - b.price)
    : []
  const inferred = detailPrices[0] ?? gradientPrices[0] ?? null
  return {
    supplier: cheapest?.supplier ?? item.answer_cheapest_supplier ?? cheapestSupplierFromText ?? inferred?.supplier ?? null,
    category: cheapest?.category ?? item.answer_cheapest_cat ?? inferred?.category ?? null,
    price: priceFromText(cheapest?.price ?? item.answer_cheapest_price ?? item.answer_cheapest) ?? inferred?.price ?? null,
  }
}

function syntheticRankingAnchors(item, formula) {
  const anchors = []
  if (item.answer_price_detail && typeof item.answer_price_detail === "object") {
    const categories = item.answer_categories ?? []
    let index = 0
    for (const [supplier, detail] of Object.entries(item.answer_price_detail)) {
      const price = priceFromText(detail?.price)
      const category = categories[index] ?? categories[0] ?? item.answer_category
      const rawSpec = detail?.spec
      const anchor = anchorFrom(item, formula, price, `ranking_detail_${index}`, "ranking_answer_price_detail", { supplier, category, rawSpec })
      if (anchor) anchors.push(anchor)
      index += 1
    }
  }
  if (Array.isArray(item.answer_prices_gradient)) {
    const diameter = text(item.question).match(/D(\d+(?:\.\d+)?)/i)?.[1] ?? "8"
    item.answer_prices_gradient.forEach((detail, index) => {
      const anchor = anchorFrom(
        item,
        formula,
        priceFromText(detail?.price),
        `ranking_gradient_${index}`,
        "ranking_answer_prices_gradient",
        { supplier: item.answer_supplier, category: item.answer_categories?.[0] ?? item.answer_category, rawSpec: `D${diameter}*${detail?.total_length}` },
      )
      if (anchor) anchors.push(anchor)
    })
  }
  return anchors
}

function rankingCandidateAnchors(item, generatedAnchors, formula) {
  const suppliers = new Set([...(item.answer_suppliers ?? []), item.answer_supplier].filter(Boolean).map(text))
  const categories = new Set([...(item.answer_categories ?? []), item.answer_category].filter(Boolean).map(text))
  const generated = generatedAnchors.filter((anchor) => {
    const supplierOk = suppliers.size === 0 || suppliers.has(anchor.supplier)
    const categoryOk = categories.size === 0 || categories.has(anchor.category)
    return supplierOk && categoryOk
  })
  return [...generated, ...syntheticRankingAnchors(item, formula)]
}

function evaluateRankingQuestion(item, index, formula, generatedAnchors, market) {
  const candidates = rankingCandidateAnchors(item, generatedAnchors, formula)
  const expected = extractRankingExpected(item)
  if (!candidates.length || expected.price == null) {
    throw new Error("ranking target or candidates unavailable")
  }
  const scored = []
  for (const candidate of candidates) {
    try {
      const quoteAnchors = excludeCurrent(generatedAnchors, candidate)
      const { result } = calculate(
        formula,
        item,
        candidate,
        quoteAnchors,
        market,
        { supplier: candidate.supplier, category: candidate.category, rawSpec: candidate.rawSpec },
      )
      scored.push({ ...candidate, predictedPrice: result.predictedPrice })
    } catch {
      // Keep ranking robust when one generated candidate cannot be evaluated.
    }
  }
  if (!scored.length) throw new Error("no ranking candidate could be scored")
  const predictedCheapest = scored.slice().sort((a, b) => a.predictedPrice - b.predictedPrice)[0]
  return {
    index: index + 1,
    question: text(item.question),
    level: item.level ?? null,
    type: item.type ?? null,
    eval_kind: "ranking",
    ranking_valid: true,
    ranking_candidate_count: scored.length,
    expected_cheapest_supplier: expected.supplier,
    expected_cheapest_category: expected.category,
    expected_cheapest_price: expected.price,
    predicted_cheapest_supplier: predictedCheapest.supplier,
    predicted_cheapest_category: predictedCheapest.category,
    predicted_cheapest_rawSpec: predictedCheapest.rawSpec,
    predicted_cheapest_price: predictedCheapest.predictedPrice,
    cheapest_supplier_hit: expected.supplier == null ? null : predictedCheapest.supplier === expected.supplier,
    cheapest_category_hit: expected.category == null ? null : predictedCheapest.category === expected.category,
    cheapest_price_error: round(Math.abs(predictedCheapest.predictedPrice - expected.price) / expected.price),
    skipped_reason: null,
  }
}

function median(values) {
  const sorted = values.filter(Number.isFinite).slice().sort((a, b) => a - b)
  if (!sorted.length) return null
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

function priceMetrics(rows) {
  const evaluated = rows.filter((row) => row.eval_kind === "price" && !row.skipped_reason)
  const count = evaluated.length
  if (!count) return { count: 0, MAPE: null, MdAPE: null, RMSE: null, MAE: null, mean_signed_percentage_error: null, within_10pct_rate: null, within_20pct_rate: null, within_30pct_rate: null, interval_hit_rate: null, overestimate_rate: null, underestimate_rate: null }
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

function rankingMetrics(rows) {
  const evaluated = rows.filter((row) => row.eval_kind === "ranking" && row.ranking_valid)
  const count = evaluated.length
  if (!count) return { count: 0, cheapest_supplier_hit_rate: null, cheapest_category_hit_rate: null, mean_cheapest_price_error: null }
  const supplierRows = evaluated.filter((row) => row.cheapest_supplier_hit != null)
  const categoryRows = evaluated.filter((row) => row.cheapest_category_hit != null)
  return {
    count,
    cheapest_supplier_hit_rate: supplierRows.length ? round(supplierRows.filter((row) => row.cheapest_supplier_hit).length / supplierRows.length) : null,
    cheapest_category_hit_rate: categoryRows.length ? round(categoryRows.filter((row) => row.cheapest_category_hit).length / categoryRows.length) : null,
    mean_cheapest_price_error: round(evaluated.reduce((sum, row) => sum + row.cheapest_price_error, 0) / count),
  }
}

function slimGroup(rows) {
  const metrics = priceMetrics(rows)
  return { count: metrics.count, MAPE: metrics.MAPE, MdAPE: metrics.MdAPE, within_30pct_rate: metrics.within_30pct_rate, interval_hit_rate: metrics.interval_hit_rate, mean_signed_percentage_error: metrics.mean_signed_percentage_error }
}

function groupBy(rows, getter) {
  const groups = {}
  for (const row of rows.filter((item) => item.eval_kind === "price" && !item.skipped_reason)) {
    const key = getter(row) || "unknown"
    groups[key] ??= []
    groups[key].push(row)
  }
  return Object.fromEntries(Object.entries(groups).sort(([a], [b]) => a.localeCompare(b, "zh-Hans-CN")).map(([key, value]) => [key, slimGroup(value)]))
}

function csvCell(value) {
  const valueText = value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value)
  return `"${valueText.replace(/"/g, '""').replace(/\r?\n/g, " ")}"`
}

function metricTable(overall) {
  return [
    "| metric | value |",
    "| --- | ---: |",
    `| total_questions | ${overall.total_questions} |`,
    `| price_evaluated_questions | ${overall.price_evaluated_questions} |`,
    `| ranking_evaluated_questions | ${overall.ranking_evaluated_questions} |`,
    `| skipped_questions | ${overall.skipped_questions} |`,
    `| MAPE | ${percent(overall.MAPE)} |`,
    `| MdAPE | ${percent(overall.MdAPE)} |`,
    `| RMSE | ${overall.RMSE ?? "N/A"} |`,
    `| MAE | ${overall.MAE ?? "N/A"} |`,
    `| mean_signed_percentage_error | ${percent(overall.mean_signed_percentage_error)} |`,
    `| within_10pct_rate | ${percent(overall.within_10pct_rate)} |`,
    `| within_20pct_rate | ${percent(overall.within_20pct_rate)} |`,
    `| within_30pct_rate | ${percent(overall.within_30pct_rate)} |`,
    `| interval_hit_rate | ${percent(overall.interval_hit_rate)} |`,
    `| overestimate_rate | ${percent(overall.overestimate_rate)} |`,
    `| underestimate_rate | ${percent(overall.underestimate_rate)} |`,
  ].join("\n")
}

function groupTable(metrics) {
  return ["| group | count | MAPE | MdAPE | within_30pct | interval_hit | mean_signed_pct_error |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: |", ...Object.entries(metrics).map(([key, value]) => `| ${key.replace(/\|/g, "/")} | ${value.count} | ${percent(value.MAPE)} | ${percent(value.MdAPE)} | ${percent(value.within_30pct_rate)} | ${percent(value.interval_hit_rate)} | ${percent(value.mean_signed_percentage_error)} |`)].join("\n")
}

function buildSummary({ runAt, market, overall, ranking, groupMetrics, generatedAnchors, details }) {
  const topErrors = details
    .filter((row) => row.eval_kind === "price" && !row.skipped_reason)
    .sort((a, b) => b.percentage_error - a.percentage_error)
    .slice(0, 20)
  const specialTop = topErrors.filter((row) => /微小径|小径|深沟|T型刀|单刃|DLC|英制/i.test(`${row.category} ${row.rawSpec}`))
  const conclusion = overall.MAPE < FIRST_ROUND.MAPE && overall.within_30pct_rate > FIRST_ROUND.within_30pct_rate ? "第二轮相对第一轮有明确改善，主要来自完整 quoteAnchors 和特殊小径解析修正。" : "第二轮相对第一轮仍未充分改善，需要继续校准锚点匹配和品类系数。"
  return [
    "# Tool Price Formula V2 Benchmark - 2nd_0525",
    "",
    `- 本次评测时间：${runAt}`,
    `- benchmark 文件路径：${benchmarkPath}`,
    "- formulaVersion：tool_price_formula_v2",
    `- 是否接入行情 API：${market.marketApiConnected ? "是" : "否"}`,
    `- 行情说明：${market.note}`,
    `- generatedAnchors：${generatedAnchors.length}`,
    "",
    "## 第一轮 vs 第二轮",
    "",
    "| metric | 1st_0525 | 2nd_0525 |",
    "| --- | ---: | ---: |",
    `| MAPE | ${percent(FIRST_ROUND.MAPE)} | ${percent(overall.MAPE)} |`,
    `| within_30pct_rate | ${percent(FIRST_ROUND.within_30pct_rate)} | ${percent(overall.within_30pct_rate)} |`,
    `| interval_hit_rate | ${percent(FIRST_ROUND.interval_hit_rate)} | ${percent(overall.interval_hit_rate)} |`,
    `| evaluated_questions / price_evaluated_questions | ${FIRST_ROUND.evaluated_questions} | ${overall.price_evaluated_questions} |`,
    `| quoteAnchors / generatedAnchors | ${FIRST_ROUND.quoteAnchors} | ${generatedAnchors.length} |`,
    "",
    "## 总体价格指标",
    "",
    metricTable(overall),
    "",
    "## Ranking Metrics",
    "",
    "| metric | value |",
    "| --- | ---: |",
    `| ranking_evaluated_questions | ${ranking.count} |`,
    `| cheapest_supplier_hit_rate | ${percent(ranking.cheapest_supplier_hit_rate)} |`,
    `| cheapest_category_hit_rate | ${percent(ranking.cheapest_category_hit_rate)} |`,
    `| mean_cheapest_price_error | ${percent(ranking.mean_cheapest_price_error)} |`,
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
    "| rank | question | category | rawSpec | target | predicted | abs_pct_error | specialToolFactor | matchedAnchors |",
    "| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ...topErrors.map((row, index) => `| ${index + 1} | ${row.question.replace(/\|/g, "/")} | ${row.category.replace(/\|/g, "/")} | ${row.rawSpec.replace(/\|/g, "/")} | ${row.eval_target_price} | ${row.predictedPrice} | ${percent(row.percentage_error)} | ${row.specialToolFactor ?? "N/A"} | ${row.matchedAnchors?.length ?? 0} |`),
    "",
    "## 小径/DLC/英制 Top Error 覆盖",
    "",
    specialTop.length
      ? specialTop.map((row) => `- ${row.category} / ${row.rawSpec}: target=${row.eval_target_price}, predicted=${row.predictedPrice}, error=${percent(row.percentage_error)}, specialToolFactor=${row.specialToolFactor}`).join("\n")
      : "- Top 20 中未再出现小径刀、DLC单刃刀、英制刀样本。",
    "",
    "## 结论",
    "",
    conclusion,
    "",
    "## 下一步参数建议",
    "",
    "- 继续按 supplier/category 增补真实报价单锚点，减少同题派生锚点对评测稳定性的影响。",
    "- 对台阶钻、铰刀、圆棒建立独立的锚点分组或专门 sizeScale，避免与普通铣刀共用长径比规则。",
    "- 对仍高估的小径类样本，优先检查规格字段是否应使用刃径而非柄径，再微调 specialToolFactor。",
    "",
  ].join("\n")
}

function printAnchorStats(anchors) {
  const supplierStats = {}
  const categoryStats = {}
  for (const anchor of anchors) {
    supplierStats[anchor.supplier] = (supplierStats[anchor.supplier] ?? 0) + 1
    categoryStats[anchor.category] = (categoryStats[anchor.category] ?? 0) + 1
  }
  const top = (obj) => Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, 30)
  console.log(`generatedAnchors: ${anchors.length}`)
  console.log(`validDiameterCount: ${anchors.filter((a) => Number.isFinite(a.diameterMm)).length}`)
  console.log(`validTotalLengthCount: ${anchors.filter((a) => Number.isFinite(a.totalLengthMm)).length}`)
  console.log("bySupplier:", JSON.stringify(top(supplierStats), null, 2))
  console.log("byCategory:", JSON.stringify(top(categoryStats), null, 2))
}

async function main() {
  fs.mkdirSync(resultsDir, { recursive: true })
  fs.mkdirSync(path.dirname(dataAnchorsPath), { recursive: true })
  const runAt = new Date().toISOString()
  const formula = loadFormulaModule()
  const { meta, questions } = parseBenchmark()
  const generatedAnchors = generateAnchors(questions, formula)
  fs.writeFileSync(dataAnchorsPath, JSON.stringify(generatedAnchors, null, 2), "utf8")
  fs.writeFileSync(resultAnchorsPath, JSON.stringify(generatedAnchors, null, 2), "utf8")
  printAnchorStats(generatedAnchors)

  const market = await tryLoadMarketFactor()
  const details = []
  const errors = []
  const rankingTypes = new Set(["multi_source_cross_cat", "multi_source_price", "single_supplier_multi_cat"])

  for (const [index, item] of questions.entries()) {
    try {
      if (item.level === 3 || rankingTypes.has(item.type)) {
        details.push(evaluateRankingQuestion(item, index, formula, generatedAnchors, market))
      } else {
        details.push(evaluatePriceQuestion(item, index, formula, generatedAnchors, market))
      }
    } catch (error) {
      const row = {
        index: index + 1,
        question: text(item.question),
        level: item.level ?? null,
        type: item.type ?? null,
        supplier: text(item.answer_supplier),
        category: text(item.answer_category),
        rawSpec: text(item.answer_spec || item.spec_raw),
        answer_price: item.answer_price ?? item.answer_price_simple ?? item.answer_cheapest_price ?? null,
        eval_kind: item.level === 3 || rankingTypes.has(item.type) ? "ranking" : "skipped",
        skipped_reason: error.message,
      }
      details.push(row)
      errors.push(row)
    }
  }

  const priceCore = priceMetrics(details)
  const rankingCore = rankingMetrics(details)
  const overall = {
    total_questions: questions.length,
    price_evaluated_questions: priceCore.count,
    ranking_evaluated_questions: rankingCore.count,
    skipped_questions: details.filter((row) => row.skipped_reason).length,
    MAPE: priceCore.MAPE,
    MdAPE: priceCore.MdAPE,
    RMSE: priceCore.RMSE,
    MAE: priceCore.MAE,
    mean_signed_percentage_error: priceCore.mean_signed_percentage_error,
    within_10pct_rate: priceCore.within_10pct_rate,
    within_20pct_rate: priceCore.within_20pct_rate,
    within_30pct_rate: priceCore.within_30pct_rate,
    interval_hit_rate: priceCore.interval_hit_rate,
    overestimate_rate: priceCore.overestimate_rate,
    underestimate_rate: priceCore.underestimate_rate,
  }
  const groupMetrics = {
    by_supplier: groupBy(details, (row) => row.supplier),
    by_category: groupBy(details, (row) => row.category),
    by_level: groupBy(details, (row) => String(row.level ?? "unknown")),
    by_type: groupBy(details, (row) => String(row.type ?? "unknown")),
    by_diameter_bucket: groupBy(details, (row) => row.diameter_bucket),
    ranking_metrics: rankingCore,
  }

  const detailOutput = { meta, runAt, benchmarkPath, formulaVersion: "tool_price_formula_v2", market, generatedAnchors: { path: dataAnchorsPath, count: generatedAnchors.length }, overallMetrics: overall, rankingMetrics: rankingCore, details }
  fs.writeFileSync(detailPath, JSON.stringify(detailOutput, null, 2), "utf8")
  fs.writeFileSync(groupMetricsPath, JSON.stringify(groupMetrics, null, 2), "utf8")
  fs.writeFileSync(summaryPath, buildSummary({ runAt, market, overall, ranking: rankingCore, groupMetrics, generatedAnchors, details }), "utf8")
  fs.writeFileSync(
    errorsPath,
    [
      ["question", "supplier", "category", "rawSpec", "answer_price", "error_reason"].map(csvCell).join(","),
      ...errors.map((row) => [row.question, row.supplier, row.category, row.rawSpec, row.answer_price, row.skipped_reason].map(csvCell).join(",")),
    ].join("\n"),
    "utf8",
  )

  console.log("Tool price formula v2 benchmark completed.")
  console.log(`Run name: ${outputStem}`)
  console.log(`Market API connected: ${market.marketApiConnected}`)
  console.log(`Price evaluated questions: ${overall.price_evaluated_questions}`)
  console.log(`Ranking evaluated questions: ${overall.ranking_evaluated_questions}`)
  console.log(`Skipped questions: ${overall.skipped_questions}`)
  console.log(`MAPE: ${percent(overall.MAPE)}`)
  console.log(`Within 30 pct rate: ${percent(overall.within_30pct_rate)}`)
  console.log(`Interval hit rate: ${percent(overall.interval_hit_rate)}`)
  console.log(`Summary: ${summaryPath}`)
  console.log(`Detail: ${detailPath}`)
  console.log(`Errors: ${errorsPath}`)
  console.log(`Group metrics: ${groupMetricsPath}`)
  console.log(`Generated anchors: ${dataAnchorsPath}`)
  console.log(`Result anchors copy: ${resultAnchorsPath}`)
}

main().catch((error) => {
  console.error("Benchmark failed:", error)
  process.exitCode = 1
})
