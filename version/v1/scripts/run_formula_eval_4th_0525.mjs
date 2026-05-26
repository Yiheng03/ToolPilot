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
const benchmarkDir = path.join(v1Dir, "benchmark")
const generatedDir = path.join(benchmarkDir, "generated")
const resultsDir = path.join(v1Dir, "results")
const outputStem = "4th_0525"

const formulaEvalGeneratedPath = path.join(generatedDir, "tool_quote_formula_eval_v1.json")
const agentEvalGeneratedPath = path.join(generatedDir, "tool_quote_agent_eval_v1.json")
const summaryPath = path.join(resultsDir, `${outputStem}_formula_summary.md`)
const detailPath = path.join(resultsDir, `${outputStem}_formula_detail.json`)
const errorsPath = path.join(resultsDir, `${outputStem}_formula_errors.csv`)
const groupMetricsPath = path.join(resultsDir, `${outputStem}_formula_group_metrics.json`)
const formulaEvalResultPath = path.join(resultsDir, `${outputStem}_formula_eval_dataset.json`)
const agentEvalResultPath = path.join(resultsDir, `${outputStem}_agent_eval_dataset.json`)
const thirdRoundDetailPath = path.join(resultsDir, "3rd_0525_detail.json")

const requireFromFrontend = createRequire(path.join(frontendDir, "package.json"))
const typescript = requireFromFrontend("typescript")

const THIRD_ROUND_FALLBACK = {
  MAPE: 0.2562,
  MdAPE: 0.1799,
  within_30pct_rate: 0.7879,
  interval_hit_rate: 0.7727,
  mean_signed_percentage_error: 0.1226,
  price_evaluated_questions: 66,
  skipped_questions: 19,
}

const RANKING_TYPES = new Set(["multi_source_cross_cat", "multi_source_price", "single_supplier_multi_cat"])
const ARRAY_MATCH_KEYWORDS = ["3D", "5D", "平刀", "球刀", "圆鼻刀", "不含税", "含税", "单价"]
const OBJECT_MATCH_KEYWORDS = ["平刀", "球刀", "圆鼻刀", "不含税", "含税", "单价"]

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

function isRankingQuestion(item) {
  return item.level === 3 || RANKING_TYPES.has(item.type)
}

function inferMaterial(category, question = "") {
  const value = `${category} ${question}`.toUpperCase()
  if (value.includes("陶瓷")) return "CERAMIC"
  if (value.includes("PCD")) return "PCD"
  if (value.includes("CBN")) return "CBN"
  if (value.includes("高速钢") || value.includes("HSS")) return "HSS"
  return "CARBIDE"
}

function buildSpecPartsFromOracle(oracle, question, formula) {
  const supplier = text(oracle.supplier)
  const category = text(oracle.category)
  const rawSpec = text(oracle.rawSpec)
  const parsed = formula.parseToolSpec(rawSpec, category)
  const drillDiameter = /3D钻头|5D钻头|深孔钻/.test(category)
    ? text(question).match(/(?:钻头直径|^|[^\d])(\d+(?:\.\d+)?)\s*mm(?:直径|的?3D|钻头)?/i)
    : null
  if (drillDiameter) {
    parsed.rawDiameterRange ??= parsed.diameterMm != null ? [parsed.diameterMm, parsed.diameterMm] : undefined
    parsed.diameterMm = Number(drillDiameter[1])
  }
  const toolKind = oracle.toolKind || formula.inferToolKind(category, rawSpec)
  const coating = oracle.coating || formula.inferCoating(category)
  const material = oracle.material || inferMaterial(category, question)
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
      taxMode: text(question).includes("不含税") ? "TAX_EXCLUDED" : text(question).includes("含税") ? "TAX_INCLUDED" : "UNKNOWN",
      ...parsed,
    },
  }
}

function buildSpecParts(item, formula, overrides = {}) {
  return buildSpecPartsFromOracle(
    {
      supplier: overrides.supplier ?? item.answer_supplier,
      category: overrides.category ?? item.answer_category,
      rawSpec: overrides.rawSpec ?? item.answer_spec ?? item.spec_raw,
      toolKind: overrides.toolKind,
      coating: overrides.coating,
      material: overrides.material,
    },
    item.question,
    formula,
  )
}

function keywordFromQuestionOrCategory(item) {
  const value = `${item.question ?? ""} ${item.answer_category ?? ""}`
  return ARRAY_MATCH_KEYWORDS.find((keyword) => value.includes(keyword)) ?? null
}

function normalizeTargetPrice(item) {
  const answerPrice = item.answer_price
  if (typeof answerPrice === "number" && validPrice(answerPrice)) {
    return {
      price: answerPrice,
      priceLabel: "单价",
      pricePickMethod: "number_direct",
      targetConfidence: "high",
      notes: "",
    }
  }

  if (answerPrice && typeof answerPrice === "object" && !Array.isArray(answerPrice)) {
    const entries = Object.entries(answerPrice)
      .map(([key, value]) => ({ key, value: Number(value) }))
      .filter((entry) => validPrice(entry.value))
    if (!entries.length) return null
    const question = text(item.question)
    for (const keyword of OBJECT_MATCH_KEYWORDS) {
      if (!question.includes(keyword)) continue
      const match = entries.find((entry) => entry.key.includes(keyword))
      if (match) {
        return {
          price: match.value,
          priceLabel: match.key,
          pricePickMethod: "object_keyword_match",
          targetConfidence: "high",
          notes: "",
        }
      }
    }
    const min = entries.slice().sort((a, b) => a.value - b.value)[0]
    return {
      price: min.value,
      priceLabel: min.key,
      pricePickMethod: "object_min_fallback",
      targetConfidence: "medium",
      notes: "多价格字段未明确，取最低价",
    }
  }

  if (Array.isArray(answerPrice)) {
    const entries = answerPrice
      .map((value, index) => ({ index, value: Number(value), label: Array.isArray(item.answer_price_labels) ? text(item.answer_price_labels[index]) : "" }))
      .filter((entry) => validPrice(entry.value))
    if (!entries.length) return null
    if (entries.length === 1) {
      return {
        price: entries[0].value,
        priceLabel: "单价",
        pricePickMethod: "array_single",
        targetConfidence: "high",
        notes: "",
      }
    }

    const keyword = keywordFromQuestionOrCategory(item)
    if (keyword) {
      const labeledMatch = entries.find((entry) => entry.label.includes(keyword))
      if (labeledMatch) {
        return {
          price: labeledMatch.value,
          priceLabel: labeledMatch.label || `array_${labeledMatch.index}`,
          pricePickMethod: "array_keyword_match",
          targetConfidence: "high",
          notes: "",
        }
      }
    }

    return {
      price: entries[0].value,
      priceLabel: `array_${entries[0].index}`,
      pricePickMethod: "array_first_low_confidence",
      targetConfidence: "low",
      notes: "数组价格语义不明确，需要人工复核",
      fullPriceArray: answerPrice,
    }
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
    rawDiameterRange: parts.parsed.rawDiameterRange,
    maxDiameterMm: parts.parsed.maxDiameterMm,
    stepCount: parts.parsed.stepCount,
    threadSize: parts.parsed.threadSize,
  }
}

function anchorFromEvalItem(evalItem, formula) {
  const parts = buildSpecPartsFromOracle(evalItem.oracle_input, evalItem.source_question, formula)
  return {
    sourceQuestion: evalItem.source_question,
    sourceType: "eval_target",
    supplier: parts.supplier,
    category: parts.category,
    rawSpec: parts.rawSpec,
    price: roundMoney(evalItem.target.price),
    priceLabel: evalItem.target.priceLabel,
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
    rawDiameterRange: parts.parsed.rawDiameterRange,
    maxDiameterMm: parts.parsed.maxDiameterMm,
    stepCount: parts.parsed.stepCount,
    threadSize: parts.parsed.threadSize,
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
  for (const item of questions) anchors.push(...anchorsFromQuestion(item, formula))
  return anchors
}

function sameIdentity(a, b) {
  return text(a.supplier) === text(b.supplier) && text(a.category) === text(b.category) && text(a.rawSpec) === text(b.rawSpec)
}

function excludeCurrent(anchors, current) {
  return anchors.filter((anchor) => {
    return !(
      sameIdentity(anchor, current) &&
      Math.abs(Number(anchor.price) - Number(current.price)) < 1e-9
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

function inferWorkpieceFactor(question, category, rawSpec) {
  const value = `${question ?? ""} ${category ?? ""} ${rawSpec ?? ""}`
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

function generateFormulaEvalDataset(questions, formula) {
  const rows = []
  for (const [index, item] of questions.entries()) {
    if (isRankingQuestion(item)) continue
    const target = normalizeTargetPrice(item)
    if (!target) continue
    const parts = buildSpecParts(item, formula)
    rows.push({
      id: item.id ?? `q_${String(index + 1).padStart(3, "0")}`,
      source_question: text(item.question),
      level: item.level ?? null,
      type: item.type ?? null,
      eval_mode: "price_formula",
      oracle_input: {
        supplier: parts.supplier,
        category: parts.category,
        rawSpec: parts.rawSpec,
        toolKind: parts.spec.toolKind,
        coating: parts.spec.coating,
        material: parts.spec.material,
        parsedSpec: parts.parsed,
      },
      target: {
        price: roundMoney(target.price),
        priceLabel: target.priceLabel || "单价",
        pricePickMethod: target.pricePickMethod,
        targetConfidence: target.targetConfidence,
      },
      includeInMape: true,
      includeInIntervalHit: true,
      notes: target.notes,
      source_index: index + 1,
    })
  }
  return rows
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

function generateAgentEvalDataset(questions) {
  return questions.map((item, index) => {
    const normalized = normalizeTargetPrice(item)
    const rankingExpected = isRankingQuestion(item) ? extractRankingExpected(item) : null
    return {
      id: item.id ?? `q_${String(index + 1).padStart(3, "0")}`,
      input: {
        question: text(item.question),
      },
      expected: {
        supplier: item.answer_supplier ?? rankingExpected?.supplier ?? null,
        category: item.answer_category ?? rankingExpected?.category ?? null,
        spec: item.answer_spec ?? item.spec_raw ?? null,
        price: normalized?.price ?? rankingExpected?.price ?? priceFromText(item.answer_price_simple) ?? null,
        priceLabel: normalized?.priceLabel ?? item.answer_price_str ?? "单价",
      },
      scoring: {
        supplier: 0.25,
        category: 0.25,
        spec: 0.25,
        price: 0.25,
      },
    }
  })
}

function calculate(formula, evalItem, quoteAnchors, market) {
  const parts = buildSpecPartsFromOracle(evalItem.oracle_input, evalItem.source_question, formula)
  const result = formula.calculateToolPriceV2({
    spec: parts.spec,
    quoteAnchors,
    fIndustry: 1,
    fProcess: inferProcessFactor(parts.spec.category),
    fWorkpiece: inferWorkpieceFactor(evalItem.source_question, parts.spec.category, parts.spec.rawSpec),
    mFuture: market.mFuture,
    precision: parts.precision,
  })
  return { parts, result, specialToolFactor: formula.getSpecialToolFactor?.(parts.spec) ?? null }
}

function evaluateFormulaItem(evalItem, index, formula, generatedAnchors, market) {
  const currentAnchor = anchorFromEvalItem(evalItem, formula)
  const quoteAnchors = excludeCurrent(generatedAnchors, currentAnchor)
  const { parts, result, specialToolFactor } = calculate(formula, evalItem, quoteAnchors, market)
  const target = evalItem.target.price
  const abs = Math.abs(result.predictedPrice - target)
  const pct = abs / target
  const signed = (result.predictedPrice - target) / target
  return {
    index: index + 1,
    id: evalItem.id,
    question: evalItem.source_question,
    level: evalItem.level ?? null,
    type: evalItem.type ?? null,
    eval_kind: "price",
    eval_mode: evalItem.eval_mode,
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
    rawDiameterRange: parts.parsed.rawDiameterRange ?? null,
    maxDiameterMm: parts.parsed.maxDiameterMm ?? null,
    stepCount: parts.parsed.stepCount ?? null,
    threadSize: parts.parsed.threadSize ?? null,
    diameter_bucket: diameterBucket(parts.parsed.diameterMm),
    eval_target_price: roundMoney(target),
    eval_price_label: evalItem.target.priceLabel,
    price_pick_method: evalItem.target.pricePickMethod,
    target_confidence: evalItem.target.targetConfidence,
    target_notes: evalItem.notes ?? "",
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
    skipped_reason: null,
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
  if (!candidates.length || expected.price == null) throw new Error("ranking target or candidates unavailable")
  const scored = []
  for (const candidate of candidates) {
    try {
      const quoteAnchors = excludeCurrent(generatedAnchors, candidate)
      const evalItem = {
        source_question: text(item.question),
        oracle_input: {
          supplier: candidate.supplier,
          category: candidate.category,
          rawSpec: candidate.rawSpec,
          toolKind: candidate.toolKind,
          coating: candidate.coating,
          material: candidate.material,
        },
      }
      const { result } = calculate(formula, evalItem, quoteAnchors, market)
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

function priceMetrics(rows, filter = () => true) {
  const evaluated = rows.filter((row) => row.eval_kind === "price" && !row.skipped_reason && filter(row))
  const count = evaluated.length
  if (!count) {
    return { count: 0, MAPE: null, MdAPE: null, RMSE: null, MAE: null, mean_signed_percentage_error: null, within_10pct_rate: null, within_20pct_rate: null, within_30pct_rate: null, interval_hit_rate: null, overestimate_rate: null, underestimate_rate: null }
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

function groupMetric(rows) {
  return priceMetrics(rows)
}

function groupBy(rows, getter) {
  const groups = {}
  for (const row of rows.filter((item) => item.eval_kind === "price" && !item.skipped_reason)) {
    const key = getter(row) || "unknown"
    groups[key] ??= []
    groups[key].push(row)
  }
  return Object.fromEntries(Object.entries(groups).sort(([a], [b]) => a.localeCompare(b, "zh-Hans-CN")).map(([key, value]) => [key, groupMetric(value)]))
}

function metricTable(metrics) {
  return [
    "| metric | value |",
    "| --- | ---: |",
    `| count | ${metrics.count} |`,
    `| MAPE | ${percent(metrics.MAPE)} |`,
    `| MdAPE | ${percent(metrics.MdAPE)} |`,
    `| MAE | ${metrics.MAE ?? "N/A"} |`,
    `| RMSE | ${metrics.RMSE ?? "N/A"} |`,
    `| within_10pct_rate | ${percent(metrics.within_10pct_rate)} |`,
    `| within_20pct_rate | ${percent(metrics.within_20pct_rate)} |`,
    `| within_30pct_rate | ${percent(metrics.within_30pct_rate)} |`,
    `| interval_hit_rate | ${percent(metrics.interval_hit_rate)} |`,
    `| mean_signed_percentage_error | ${percent(metrics.mean_signed_percentage_error)} |`,
    `| overestimate_rate | ${percent(metrics.overestimate_rate)} |`,
    `| underestimate_rate | ${percent(metrics.underestimate_rate)} |`,
  ].join("\n")
}

function groupTable(metrics) {
  const rows = Object.entries(metrics)
  if (!rows.length) return "_No evaluated rows._"
  return [
    "| group | count | MAPE | MdAPE | within_30pct | interval_hit | mean_signed_pct_error |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ...rows.map(([key, value]) => `| ${key.replace(/\|/g, "/")} | ${value.count} | ${percent(value.MAPE)} | ${percent(value.MdAPE)} | ${percent(value.within_30pct_rate)} | ${percent(value.interval_hit_rate)} | ${percent(value.mean_signed_percentage_error)} |`),
  ].join("\n")
}

function categoryBias(rows, direction) {
  const groups = {}
  for (const row of rows.filter((item) => item.eval_kind === "price" && !item.skipped_reason)) {
    groups[row.category] ??= []
    groups[row.category].push(row)
  }
  return Object.entries(groups)
    .map(([category, items]) => ({
      category,
      count: items.length,
      mean_signed_percentage_error: round(items.reduce((sum, item) => sum + item.signed_percentage_error, 0) / items.length),
      MAPE: priceMetrics(items).MAPE,
    }))
    .filter((item) => (direction === "over" ? item.mean_signed_percentage_error > 0 : item.mean_signed_percentage_error < 0))
    .sort((a, b) => direction === "over" ? b.mean_signed_percentage_error - a.mean_signed_percentage_error : a.mean_signed_percentage_error - b.mean_signed_percentage_error)
    .slice(0, 10)
}

function categoryBiasTable(rows) {
  if (!rows.length) return "_No category bias rows._"
  return [
    "| rank | category | count | mean_signed_percentage_error | MAPE |",
    "| ---: | --- | ---: | ---: | ---: |",
    ...rows.map((row, index) => `| ${index + 1} | ${row.category.replace(/\|/g, "/")} | ${row.count} | ${percent(row.mean_signed_percentage_error)} | ${percent(row.MAPE)} |`),
  ].join("\n")
}

function lowConfidenceTable(rows) {
  const low = rows.filter((row) => row.eval_kind === "price" && row.target_confidence === "low")
  if (!low.length) return "_No low confidence target rows._"
  return [
    "| id | question | category | rawSpec | target | method | notes |",
    "| --- | --- | --- | --- | ---: | --- | --- |",
    ...low.map((row) => `| ${row.id} | ${row.question.replace(/\|/g, "/")} | ${row.category.replace(/\|/g, "/")} | ${row.rawSpec.replace(/\|/g, "/")} | ${row.eval_target_price} | ${row.price_pick_method} | ${row.target_notes.replace(/\|/g, "/")} |`),
  ].join("\n")
}

function topErrorsTable(rows) {
  const top = rows
    .filter((row) => row.eval_kind === "price" && !row.skipped_reason)
    .sort((a, b) => b.percentage_error - a.percentage_error)
    .slice(0, 20)
  return [
    "| rank | id | question | category | rawSpec | target | predicted | abs_pct_error | confidence | method | matchedAnchors |",
    "| ---: | --- | --- | --- | --- | ---: | ---: | ---: | --- | --- | ---: |",
    ...top.map((row, index) => `| ${index + 1} | ${row.id} | ${row.question.replace(/\|/g, "/")} | ${row.category.replace(/\|/g, "/")} | ${row.rawSpec.replace(/\|/g, "/")} | ${row.eval_target_price} | ${row.predictedPrice} | ${percent(row.percentage_error)} | ${row.target_confidence} | ${row.price_pick_method} | ${row.matchedAnchors?.length ?? 0} |`),
  ].join("\n")
}

function loadThirdRoundMetrics() {
  if (!fs.existsSync(thirdRoundDetailPath)) return THIRD_ROUND_FALLBACK
  const parsed = JSON.parse(fs.readFileSync(thirdRoundDetailPath, "utf8"))
  return parsed.overallMetrics ?? THIRD_ROUND_FALLBACK
}

async function fetchMarketRows(url) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 2500)
  try {
    const response = await fetch(url, { signal: controller.signal })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } finally {
    clearTimeout(timeout)
  }
}

async function loadMarketAdjusted() {
  const urls = [
    "http://127.0.0.1:8765/api/market/production-forecasts?horizon_day=30",
    "http://localhost:3000/api/market/production-forecasts?horizon_day=30",
  ]
  const failures = []
  for (const url of urls) {
    try {
      const payload = await fetchMarketRows(url)
      const rows = Array.isArray(payload) ? payload : payload.items ?? payload.data ?? []
      const returns = rows
        .filter((row) => Number(row.horizon_day ?? row.horizonDay ?? 30) === 30 || row.horizon_day == null)
        .map((row) => Number(row.final_predicted_return ?? row.predicted_return ?? row.forecast_return))
        .filter(Number.isFinite)
      if (!returns.length) throw new Error("no usable 30-day return fields")
      const avg = returns.reduce((sum, value) => sum + value, 0) / returns.length
      return {
        mode: "market_adjusted",
        status: "completed",
        marketApiConnected: true,
        marketApiUrl: url,
        rowsUsed: returns.length,
        mFuture: Math.max(0.85, Math.min(1.15, 1 + avg)),
        rG: 1,
        rQ: 1,
        note: `读取本机 /api/market/production-forecasts 30 天预测，使用 ${returns.length} 条收益率计算 mFuture。`,
      }
    } catch (error) {
      failures.push(`${url}: ${error.message}`)
    }
  }
  return {
    mode: "market_adjusted",
    status: "unavailable",
    marketApiConnected: false,
    marketApiUrl: urls.join(" ; "),
    mFuture: 1,
    rG: 1,
    rQ: 1,
    note: `market_adjusted 不可用：${failures.join(" | ")}`,
  }
}

function evaluateFormulaDataset(formulaEvalDataset, formula, generatedAnchors, market) {
  const details = []
  for (const [index, evalItem] of formulaEvalDataset.entries()) {
    try {
      details.push(evaluateFormulaItem(evalItem, index, formula, generatedAnchors, market))
    } catch (error) {
      details.push({
        index: index + 1,
        id: evalItem.id,
        question: evalItem.source_question,
        level: evalItem.level ?? null,
        type: evalItem.type ?? null,
        supplier: evalItem.oracle_input?.supplier ?? null,
        category: evalItem.oracle_input?.category ?? null,
        rawSpec: evalItem.oracle_input?.rawSpec ?? null,
        eval_kind: "price",
        skipped_reason: error.message,
      })
    }
  }
  return details
}

function evaluateRanking(questions, formula, generatedAnchors, market) {
  const rows = []
  for (const [index, item] of questions.entries()) {
    if (!isRankingQuestion(item)) continue
    try {
      rows.push(evaluateRankingQuestion(item, index, formula, generatedAnchors, market))
    } catch (error) {
      rows.push({
        index: index + 1,
        question: text(item.question),
        level: item.level ?? null,
        type: item.type ?? null,
        eval_kind: "ranking",
        ranking_valid: false,
        skipped_reason: error.message,
      })
    }
  }
  return rows
}

function buildGroupMetrics(details, rankingRows) {
  return {
    by_level: groupBy(details, (row) => String(row.level ?? "unknown")),
    by_type: groupBy(details, (row) => String(row.type ?? "unknown")),
    by_supplier: groupBy(details, (row) => row.supplier),
    by_category: groupBy(details, (row) => row.category),
    by_diameter_bucket: groupBy(details, (row) => row.diameter_bucket),
    by_target_confidence: groupBy(details, (row) => row.target_confidence),
    ranking_metrics: rankingMetrics(rankingRows),
  }
}

function csvCell(value) {
  const valueText = value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value)
  return `"${valueText.replace(/"/g, '""').replace(/\r?\n/g, " ")}"`
}

function writeErrorsCsv(details) {
  const rows = details
    .filter((row) => row.eval_kind === "price")
    .sort((a, b) => (b.percentage_error ?? -1) - (a.percentage_error ?? -1))
  fs.writeFileSync(
    errorsPath,
    [
      ["id", "question", "supplier", "category", "rawSpec", "target", "predicted", "abs_pct_error", "target_confidence", "price_pick_method", "notes", "error_reason"].map(csvCell).join(","),
      ...rows.map((row) => [row.id, row.question, row.supplier, row.category, row.rawSpec, row.eval_target_price, row.predictedPrice, row.percentage_error, row.target_confidence, row.price_pick_method, row.target_notes, row.skipped_reason].map(csvCell).join(",")),
    ].join("\n"),
    "utf8",
  )
}

function buildSummary({ runAt, formulaVersion, generatedAnchors, formulaEvalDataset, agentEvalDataset, neutral, marketAdjusted, rankingRows, groupMetrics }) {
  const third = loadThirdRoundMetrics()
  const allMetrics = priceMetrics(neutral.details)
  const highMetrics = priceMetrics(neutral.details, (row) => row.target_confidence === "high")
  const mediumHighMetrics = priceMetrics(neutral.details, (row) => row.target_confidence === "high" || row.target_confidence === "medium")
  const ranking = rankingMetrics(rankingRows)
  const marketAdjustedMetrics = marketAdjusted.status === "completed" ? priceMetrics(marketAdjusted.details) : null
  return [
    "# Price Formula Benchmark - 4th_0525",
    "",
    "## 本次评测性质说明",
    "",
    `本次为 Price Formula Benchmark，使用 oracle supplier/category/spec 输入，仅评估 ${formulaVersion} 的规格报价能力，不评估大模型自然语言问答、检索和多供应商推荐能力。`,
    "",
    `- run_at: ${runAt}`,
    `- benchmark: ${benchmarkPath}`,
    `- formulaVersion: ${formulaVersion}`,
    `- formula_eval_dataset: ${formulaEvalDataset.length}`,
    `- agent_eval_dataset: ${agentEvalDataset.length}`,
    `- generatedAnchors: ${generatedAnchors.length}`,
    "",
    "## 行情模式状态",
    "",
    `- neutral_market: completed, mFuture=1.0，仅评估规格报价逻辑。`,
    `- market_adjusted: ${marketAdjusted.status}${marketAdjusted.status === "completed" ? `, mFuture=${marketAdjusted.mFuture.toFixed(6)}, rowsUsed=${marketAdjusted.rowsUsed}` : ""}`,
    `- market_adjusted_note: ${marketAdjusted.note}`,
    "",
    "不能把 neutral_market 结果说成行情联动结果；只有 market_adjusted completed 时才代表行情联动评测。",
    "",
    "## 第三轮 vs 第四轮",
    "",
    "| metric | 3rd_0525 | 4th_0525 neutral_market |",
    "| --- | ---: | ---: |",
    `| MAPE | ${percent(third.MAPE)} | ${percent(allMetrics.MAPE)} |`,
    `| MdAPE | ${percent(third.MdAPE)} | ${percent(allMetrics.MdAPE)} |`,
    `| within_30pct_rate | ${percent(third.within_30pct_rate)} | ${percent(allMetrics.within_30pct_rate)} |`,
    `| interval_hit_rate | ${percent(third.interval_hit_rate)} | ${percent(allMetrics.interval_hit_rate)} |`,
    `| mean_signed_percentage_error | ${percent(third.mean_signed_percentage_error)} | ${percent(allMetrics.mean_signed_percentage_error)} |`,
    `| price_evaluated_questions | ${third.price_evaluated_questions} | ${allMetrics.count} |`,
    `| skipped_questions | ${third.skipped_questions} | ${neutral.skippedCount} |`,
    "",
    "## 全量价格指标",
    "",
    "### all_price_eval",
    "",
    metricTable(allMetrics),
    "",
    "### high_confidence_only",
    "",
    metricTable(highMetrics),
    "",
    "### medium_high_confidence_only",
    "",
    metricTable(mediumHighMetrics),
    "",
    "## market_adjusted 指标",
    "",
    marketAdjustedMetrics ? metricTable(marketAdjustedMetrics) : `_market_adjusted unavailable: ${marketAdjusted.note}_`,
    "",
    "## 分组指标",
    "",
    "### by_level",
    "",
    groupTable(groupMetrics.by_level),
    "",
    "### by_type",
    "",
    groupTable(groupMetrics.by_type),
    "",
    "### by_supplier",
    "",
    groupTable(groupMetrics.by_supplier),
    "",
    "### by_category",
    "",
    groupTable(groupMetrics.by_category),
    "",
    "### by_diameter_bucket",
    "",
    groupTable(groupMetrics.by_diameter_bucket),
    "",
    "### by_target_confidence",
    "",
    groupTable(groupMetrics.by_target_confidence),
    "",
    "## Ranking 单独说明",
    "",
    "Ranking_eval 不纳入 MAPE。当前 ranking 指标用于后续 agent / retrieval / recommendation 评测，不代表单品报价公式能力。",
    "",
    "| metric | value |",
    "| --- | ---: |",
    `| ranking_evaluated_questions | ${ranking.count} |`,
    `| cheapest_supplier_hit_rate | ${percent(ranking.cheapest_supplier_hit_rate)} |`,
    `| cheapest_category_hit_rate | ${percent(ranking.cheapest_category_hit_rate)} |`,
    `| mean_cheapest_price_error | ${percent(ranking.mean_cheapest_price_error)} |`,
    "",
    "## Top 20 误差最大样本",
    "",
    topErrorsTable(neutral.details),
    "",
    "## Top 10 高估品类",
    "",
    categoryBiasTable(categoryBias(neutral.details, "over")),
    "",
    "## Top 10 低估品类",
    "",
    categoryBiasTable(categoryBias(neutral.details, "under")),
    "",
    "## 低置信度 target 样本列表",
    "",
    lowConfidenceTable(neutral.details),
    "",
  ].join("\n")
}

async function main() {
  fs.mkdirSync(generatedDir, { recursive: true })
  fs.mkdirSync(resultsDir, { recursive: true })

  const runAt = new Date().toISOString()
  const formula = loadFormulaModule()
  const formulaVersion = formula.TOOL_PRICE_FORMULA_VERSION
  if (formulaVersion !== "tool_price_formula_v2_calibrated_20260526") {
    throw new Error(`Unexpected formula version: ${formulaVersion}`)
  }

  const { meta, questions } = parseBenchmark()
  const formulaEvalDataset = generateFormulaEvalDataset(questions, formula)
  const agentEvalDataset = generateAgentEvalDataset(questions)
  const generatedAnchors = generateAnchors(questions, formula)
  const neutralMarket = {
    mode: "neutral_market",
    status: "completed",
    marketApiConnected: false,
    marketApiUrl: null,
    mFuture: 1,
    rG: 1,
    rQ: 1,
    note: "neutral_market 使用 mFuture=1.0，只评估规格报价逻辑。",
  }
  const marketAdjusted = await loadMarketAdjusted()

  const neutralDetails = evaluateFormulaDataset(formulaEvalDataset, formula, generatedAnchors, neutralMarket)
  const marketAdjustedDetails = marketAdjusted.status === "completed"
    ? evaluateFormulaDataset(formulaEvalDataset, formula, generatedAnchors, marketAdjusted)
    : []
  const rankingRows = evaluateRanking(questions, formula, generatedAnchors, neutralMarket)
  const groupMetrics = buildGroupMetrics(neutralDetails, rankingRows)
  const neutralMetrics = priceMetrics(neutralDetails)
  const highConfidenceCount = neutralDetails.filter((row) => row.eval_kind === "price" && row.target_confidence === "high" && !row.skipped_reason).length

  const neutral = {
    market: neutralMarket,
    details: neutralDetails,
    metrics: {
      all_price_eval: neutralMetrics,
      high_confidence_only: priceMetrics(neutralDetails, (row) => row.target_confidence === "high"),
      medium_high_confidence_only: priceMetrics(neutralDetails, (row) => row.target_confidence === "high" || row.target_confidence === "medium"),
    },
    skippedCount: questions.filter((item) => !isRankingQuestion(item)).length - formulaEvalDataset.length + neutralDetails.filter((row) => row.skipped_reason).length,
  }

  const detailOutput = {
    meta,
    runAt,
    benchmarkPath,
    formulaVersion,
    benchmarkSplitReadme: path.join(benchmarkDir, "README_benchmark_split.md"),
    generatedAnchors: { count: generatedAnchors.length },
    neutral_market: neutral,
    market_adjusted: {
      market: marketAdjusted,
      status: marketAdjusted.status,
      details: marketAdjustedDetails,
      metrics: marketAdjusted.status === "completed" ? priceMetrics(marketAdjustedDetails) : null,
    },
    ranking_eval: {
      note: "ranking_eval is separate and not included in MAPE.",
      metrics: rankingMetrics(rankingRows),
      details: rankingRows,
    },
  }

  fs.writeFileSync(formulaEvalGeneratedPath, JSON.stringify(formulaEvalDataset, null, 2), "utf8")
  fs.writeFileSync(agentEvalGeneratedPath, JSON.stringify(agentEvalDataset, null, 2), "utf8")
  fs.writeFileSync(formulaEvalResultPath, JSON.stringify(formulaEvalDataset, null, 2), "utf8")
  fs.writeFileSync(agentEvalResultPath, JSON.stringify(agentEvalDataset, null, 2), "utf8")
  fs.writeFileSync(detailPath, JSON.stringify(detailOutput, null, 2), "utf8")
  fs.writeFileSync(groupMetricsPath, JSON.stringify(groupMetrics, null, 2), "utf8")
  fs.writeFileSync(summaryPath, buildSummary({ runAt, formulaVersion, generatedAnchors, formulaEvalDataset, agentEvalDataset, neutral, marketAdjusted: { ...marketAdjusted, details: marketAdjustedDetails }, rankingRows, groupMetrics }), "utf8")
  writeErrorsCsv(neutralDetails)

  console.log(`formula version: ${formulaVersion}`)
  console.log(`formula_eval samples: ${formulaEvalDataset.length}`)
  console.log(`high confidence samples: ${highConfidenceCount}`)
  console.log(`neutral_market MAPE: ${percent(neutralMetrics.MAPE)}`)
  console.log(`neutral_market MdAPE: ${percent(neutralMetrics.MdAPE)}`)
  console.log(`neutral_market within_30pct_rate: ${percent(neutralMetrics.within_30pct_rate)}`)
  console.log(`market_adjusted available: ${marketAdjusted.status === "completed"}`)
  if (marketAdjusted.status !== "completed") console.log(`market_adjusted reason: ${marketAdjusted.note}`)
  console.log(`agent_eval dataset samples: ${agentEvalDataset.length}`)
  console.log(`summary: ${summaryPath}`)
  console.log(`detail: ${detailPath}`)
  console.log(`errors: ${errorsPath}`)
  console.log(`group metrics: ${groupMetricsPath}`)
  console.log(`formula eval dataset: ${formulaEvalResultPath}`)
  console.log(`agent eval dataset: ${agentEvalResultPath}`)
  console.log(`generated formula eval dataset: ${formulaEvalGeneratedPath}`)
  console.log(`generated agent eval dataset: ${agentEvalGeneratedPath}`)
}

main().catch((error) => {
  console.error("Formula eval failed:", error)
  process.exitCode = 1
})
