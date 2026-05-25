export type ToolKind =
  | "END_MILL"
  | "BALL_END_MILL"
  | "CORNER_RADIUS_END_MILL"
  | "ROUGHING_END_MILL"
  | "DRILL"
  | "REAMER"
  | "STEP_DRILL"
  | "ROD"
  | "INSERT"
  | "BORING_TOOL"

export type ToolMaterial = "CARBIDE" | "HSS" | "CERAMIC" | "PCD" | "CBN" | "STEEL_HOLDER"

export type ToolCoating =
  | "UNCOATED"
  | "BRONZE"
  | "BLACK_NANO"
  | "BLUE_NANO"
  | "DLC"
  | "RAINBOW"
  | "ALTIN"
  | "TIALN"
  | "CHAMPAGNE"
  | "UNKNOWN"

export interface ToolQuoteSpec {
  supplier?: string
  category: string
  toolKind: ToolKind
  material: ToolMaterial
  coating: ToolCoating
  diameterMm?: number
  radiusMm?: number
  fluteLengthMm?: number
  totalLengthMm?: number
  shankDiameterMm?: number
  fluteCount?: number
  helixAngleDeg?: number
  hardnessDegree?: 45 | 50 | 55 | 58 | 60 | 65 | 68
  cornerRadiusMm?: number
  tolerance?: string
  stepInfo?: string
  rawSpec?: string
  taxMode?: "TAX_INCLUDED" | "TAX_EXCLUDED" | "UNKNOWN"
}

export interface QuoteAnchor {
  supplier: string
  category: string
  toolKind: ToolQuoteSpec["toolKind"]
  material: ToolQuoteSpec["material"]
  coating: ToolQuoteSpec["coating"]
  diameterMm?: number
  fluteLengthMm?: number
  totalLengthMm?: number
  shankDiameterMm?: number
  fluteCount?: number
  radiusMm?: number
  tolerance?: string
  rawSpec: string
  price: number
  priceLabel?: string
}

export interface RawQuoteAnchor {
  supplier: string
  category: string
  rawSpec: string
  price: number
  priceLabel?: string
  toolKind?: ToolKind
  material?: ToolMaterial
  coating?: ToolCoating
}

export interface MatchedQuoteAnchor extends QuoteAnchor {
  similarityWeight: number
  geometryDistance: number
  sizeScale: number
  adjustedPrice: number
  matchLevel: "exact" | "high" | "medium" | "low"
}

export interface SpecPriceResult {
  specBasePrice: number
  matchedAnchors: MatchedQuoteAnchor[]
  source: "exact_quote" | "anchor" | "fallback"
  bestSimilarity: number
  explanation: string[]
}

export interface ToolPriceV2Result {
  predictedPrice: number
  lowerPrice: number
  upperPrice: number
  intervalRate: number
  specBasePrice: number
  matchedAnchors: MatchedQuoteAnchor[]
  formulaVersion: "tool_price_formula_v2"
  explanation: string[]
}

export const toolKindFactor: Record<ToolKind, number> = {
  END_MILL: 1,
  BALL_END_MILL: 1.08,
  CORNER_RADIUS_END_MILL: 1.14,
  ROUGHING_END_MILL: 1.22,
  DRILL: 0.82,
  REAMER: 1.18,
  STEP_DRILL: 1.65,
  ROD: 0.72,
  INSERT: 0.45,
  BORING_TOOL: 1.2,
}

export const coatingFactor: Record<ToolCoating, number> = {
  UNCOATED: 0.92,
  BRONZE: 1,
  CHAMPAGNE: 1.05,
  BLACK_NANO: 1.18,
  BLUE_NANO: 1.25,
  RAINBOW: 1.12,
  DLC: 1.28,
  ALTIN: 1.22,
  TIALN: 1.2,
  UNKNOWN: 1,
}

export const materialFactor: Record<ToolMaterial, number> = {
  CARBIDE: 1,
  HSS: 0.55,
  CERAMIC: 0.85,
  PCD: 2.8,
  CBN: 2.4,
  STEEL_HOLDER: 0.65,
}

const fallbackRefPrice: Record<ToolKind, number> = {
  END_MILL: 55,
  BALL_END_MILL: 65,
  CORNER_RADIUS_END_MILL: 70,
  ROUGHING_END_MILL: 95,
  DRILL: 38,
  REAMER: 75,
  STEP_DRILL: 130,
  ROD: 115,
  INSERT: 35,
  BORING_TOOL: 70,
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value))
}

function round2(value: number) {
  return Number((Number.isFinite(value) ? value : 0).toFixed(2))
}

function positive(value: number | undefined, fallback: number) {
  return Number.isFinite(value) && Number(value) > 0 ? Number(value) : fallback
}

function parseDimensionToken(token: string) {
  const cleaned = token.trim().replace(/,/g, ".")
  const mixed = cleaned.match(/^(\d+)-(\d+)\/(\d+)/)
  if (mixed) {
    return (Number(mixed[1]) + Number(mixed[2]) / Number(mixed[3])) * 25.4
  }
  const fraction = cleaned.match(/^(\d+)\/(\d+)/)
  if (fraction) {
    return (Number(fraction[1]) / Number(fraction[2])) * 25.4
  }
  const decimal = cleaned.match(/\d+(?:\.\d+)?/)
  return decimal ? Number(decimal[0]) : undefined
}

function getLabeledNumber(rawSpec: string, label: string) {
  const match = rawSpec.match(new RegExp(`${label}\\s*(\\d+(?:\\.\\d+)?)`, "i"))
  return match ? Number(match[1]) : undefined
}

function applyOrderedDimensions(result: Partial<ToolQuoteSpec>, values: number[]) {
  if (!values.length) return
  if (result.diameterMm == null) {
    result.diameterMm = values[0]
  }

  const remaining = values.slice(1)
  if (remaining.length === 1) {
    result.totalLengthMm ??= remaining[0]
  } else if (remaining.length === 2) {
    result.fluteLengthMm ??= remaining[0]
    result.totalLengthMm ??= remaining[1]
  } else if (remaining.length >= 3) {
    if (Math.abs(remaining[0] - (result.diameterMm ?? remaining[0])) < 0.001) {
      result.shankDiameterMm ??= remaining[0]
      result.fluteLengthMm ??= remaining[1]
      result.totalLengthMm ??= remaining[2]
    } else {
      result.fluteLengthMm ??= remaining[0]
      result.shankDiameterMm ??= remaining[1]
      result.totalLengthMm ??= remaining[2]
    }
  }
}

export function parseToolSpec(rawSpec: string, category?: string): Partial<ToolQuoteSpec> {
  const result: Partial<ToolQuoteSpec> = { rawSpec }
  const text = rawSpec.trim()
  if (!text) return result

  const normalized = text
    .replace(/[ΦφØø⌀]/g, "D")
    .replace(/[×x]/g, "*")
    .replace(/\s+/g, " ")
    .toUpperCase()

  const tolerance = normalized.match(/\bH\d+\b/)
  if (tolerance) {
    result.tolerance = tolerance[0]
  }

  const fluteCount = normalized.match(/(\d+)\s*[FT]\b/)
  if (fluteCount) {
    result.fluteCount = Number(fluteCount[1])
  }

  const radius = getLabeledNumber(normalized, "R")
  if (radius != null) {
    result.radiusMm = radius
    result.cornerRadiusMm = radius
  }

  const diameter = getLabeledNumber(normalized, "D")
  if (diameter != null) {
    result.diameterMm = diameter
  }

  const totalLength = normalized.match(/(\d+(?:\.\d+)?|\d+-\d+\/\d+|\d+\/\d+)\s*L\b/)
  if (totalLength) {
    result.totalLengthMm = parseDimensionToken(totalLength[1])
  }

  const dimensionPart = normalized.replace(/\bH\d+\b/g, "")
  const tokens = dimensionPart.split(/[*\s]+/).filter(Boolean)
  const numericValues: number[] = []

  for (const token of tokens) {
    if (/^\d+\s*[FT]$/.test(token) || /^M\d+/.test(token) || /°/.test(token)) continue
    if (/^\d+(?:\.\d+)?H$/.test(token)) continue
    if (/^R\d/.test(token)) continue

    if (/^\d+-\d+\/\d+/.test(token) || /^\d+\/\d+/.test(token)) {
      const value = parseDimensionToken(token)
      if (value != null && Number.isFinite(value)) {
        numericValues.push(value)
      }
      continue
    }

    const range = token.match(/^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)/)
    if (range) {
      numericValues.push(Number(range[1]))
      continue
    }

    const value = parseDimensionToken(token)
    if (value != null && Number.isFinite(value)) {
      numericValues.push(value)
    }
  }

  applyOrderedDimensions(result, numericValues)

  const helixAngle = normalized.match(/(\d+(?:\.\d+)?)\s*(?:DEG|°)/)
  if (helixAngle) {
    result.helixAngleDeg = Number(helixAngle[1])
  }

  if (category) {
    result.category = category
  }

  return result
}

export function inferToolKind(category: string, rawSpec = ""): ToolKind {
  const text = `${category} ${rawSpec}`.toUpperCase()
  if (text.includes("台阶钻") || text.includes("STEP_DRILL")) return "STEP_DRILL"
  if (text.includes("球刀") || text.includes("BALL")) return "BALL_END_MILL"
  if (text.includes("圆鼻") || text.includes("内R") || text.includes("R角") || text.includes("CORNER")) return "CORNER_RADIUS_END_MILL"
  if (text.includes("粗皮") || text.includes("ROUGH")) return "ROUGHING_END_MILL"
  if (text.includes("铰刀") || text.includes("REAMER")) return "REAMER"
  if (text.includes("钻") || text.includes("DRILL")) return "DRILL"
  if (text.includes("圆棒") || text.includes("ROD")) return "ROD"
  if (text.includes("镗刀") || text.includes("BORING")) return "BORING_TOOL"
  if (text.includes("车刀") || text.includes("刀片") || text.includes("INSERT")) return "INSERT"
  return "END_MILL"
}

export function inferCoating(category: string): ToolCoating {
  const text = category.toUpperCase()
  if (text.includes("不涂层") || text.includes("光刀") || text.includes("UNCOATED")) return "UNCOATED"
  if (text.includes("古铜") || text.includes("BRONZE")) return "BRONZE"
  if (text.includes("黑纳米") || text.includes("BLACK_NANO") || text.includes("黑")) return "BLACK_NANO"
  if (text.includes("蓝纳米") || text.includes("BLUE_NANO") || text.includes("蓝")) return "BLUE_NANO"
  if (text.includes("DLC")) return "DLC"
  if (text.includes("七彩") || text.includes("RAINBOW")) return "RAINBOW"
  if (text.includes("香槟金") || text.includes("CHAMPAGNE")) return "CHAMPAGNE"
  if (text.includes("ALTIN")) return "ALTIN"
  if (text.includes("TIALN")) return "TIALN"
  return "UNKNOWN"
}

export function getLongToolFactor(diameterMm?: number, totalLengthMm?: number) {
  const diameter = positive(diameterMm, 6)
  const totalLength = positive(totalLengthMm, 50)
  const slenderness = totalLength / diameter
  if (slenderness <= 8) return 1
  if (slenderness <= 12) return 1.12
  if (slenderness <= 16) return 1.28
  if (slenderness <= 22) return 1.55
  return 1.85
}

export function getPrecisionFactor(tolerance?: string, precision = 50) {
  if (tolerance?.toUpperCase() === "H7") return 1.18
  if (precision > 75) return 1.2
  if (precision > 50) return 1.08
  return 1
}

function getGeometryDistance(input: ToolQuoteSpec, anchor: QuoteAnchor) {
  const anchorD = positive(anchor.diameterMm, positive(input.diameterMm, 6))
  const anchorTotalLength = positive(anchor.totalLengthMm, positive(input.totalLengthMm, 50))
  const anchorFluteLength = positive(anchor.fluteLengthMm, positive(input.fluteLengthMm, anchorTotalLength))
  const targetD = positive(input.diameterMm, anchorD)
  const targetTotalLength = positive(input.totalLengthMm, anchorTotalLength)
  const targetFluteLength = positive(input.fluteLengthMm, anchorFluteLength)
  const targetFluteCount = positive(input.fluteCount, positive(anchor.fluteCount, 0))
  const anchorFluteCount = positive(anchor.fluteCount, targetFluteCount)

  return (
    2.2 * Math.abs(Math.log(targetD / anchorD)) +
    0.8 * Math.abs(Math.log(targetTotalLength / anchorTotalLength)) +
    0.6 * Math.abs(Math.log(targetFluteLength / anchorFluteLength)) +
    0.25 * Math.abs(targetFluteCount - anchorFluteCount)
  )
}

function getSizeScale(input: ToolQuoteSpec, anchor: QuoteAnchor) {
  const anchorD = positive(anchor.diameterMm, positive(input.diameterMm, 6))
  const anchorTotalLength = positive(anchor.totalLengthMm, positive(input.totalLengthMm, 50))
  const anchorFluteLength = positive(anchor.fluteLengthMm, positive(input.fluteLengthMm, anchorTotalLength))
  const targetD = positive(input.diameterMm, anchorD)
  const targetTotalLength = positive(input.totalLengthMm, anchorTotalLength)
  const targetFluteLength = positive(input.fluteLengthMm, anchorFluteLength)

  return clamp(
    Math.pow(targetD / anchorD, 1.35) *
      Math.pow(targetTotalLength / anchorTotalLength, 0.55) *
      Math.pow(targetFluteLength / anchorFluteLength, 0.25),
    0.35,
    4.5,
  )
}

function scopeRank(input: ToolQuoteSpec, anchor: QuoteAnchor) {
  if (
    input.supplier &&
    input.supplier === anchor.supplier &&
    input.category === anchor.category &&
    input.toolKind === anchor.toolKind &&
    input.coating === anchor.coating
  ) {
    return 1
  }
  if (input.category === anchor.category && input.toolKind === anchor.toolKind && input.coating === anchor.coating) {
    return 2
  }
  if (input.toolKind === anchor.toolKind && input.material === anchor.material && input.coating === anchor.coating) {
    return 3
  }
  if (input.toolKind === anchor.toolKind && input.material === anchor.material) {
    return 4
  }
  return 0
}

function getFallbackBasePrice(input: ToolQuoteSpec, precision = 50) {
  const diameter = positive(input.diameterMm, 6)
  const totalLength = positive(input.totalLengthMm, 50)
  return (
    fallbackRefPrice[input.toolKind] *
    Math.pow(diameter / 6, 1.35) *
    Math.pow(totalLength / 50, 0.55) *
    materialFactor[input.material] *
    coatingFactor[input.coating] *
    getLongToolFactor(diameter, totalLength) *
    getPrecisionFactor(input.tolerance, precision)
  )
}

export function calculateSpecBasePrice(input: ToolQuoteSpec, anchors: QuoteAnchor[], precision = 50): SpecPriceResult {
  const scoped = anchors
    .map((anchor) => ({ anchor, rank: scopeRank(input, anchor) }))
    .filter((item) => item.rank > 0)
    .sort((a, b) => a.rank - b.rank)

  const bestRank = scoped[0]?.rank
  const candidates = scoped
    .filter((item) => item.rank === bestRank)
    .map(({ anchor }) => {
      const geometryDistance = getGeometryDistance(input, anchor)
      const similarityWeight = Math.exp(-geometryDistance)
      const sizeScale = getSizeScale(input, anchor)
      const adjustedPrice = anchor.price * sizeScale
      const matchLevel =
        geometryDistance <= 0.02 ? "exact" : similarityWeight >= 0.65 ? "high" : similarityWeight >= 0.35 ? "medium" : "low"

      return {
        ...anchor,
        geometryDistance,
        similarityWeight,
        sizeScale,
        adjustedPrice,
        matchLevel,
      } satisfies MatchedQuoteAnchor
    })
    .sort((a, b) => a.geometryDistance - b.geometryDistance)
    .slice(0, 5)

  if (candidates.length > 0) {
    const weightTotal = candidates.reduce((sum, item) => sum + item.similarityWeight, 0)
    const weightedPrice = candidates.reduce((sum, item) => sum + item.adjustedPrice * item.similarityWeight, 0) / positive(weightTotal, 1)
    const bestSimilarity = candidates[0]?.similarityWeight ?? 0

    return {
      specBasePrice: round2(weightedPrice),
      matchedAnchors: candidates.map((item) => ({ ...item, adjustedPrice: round2(item.adjustedPrice), sizeScale: round2(item.sizeScale) })),
      source: candidates[0]?.matchLevel === "exact" ? "exact_quote" : "anchor",
      bestSimilarity,
      explanation: [
        `锚点定价：命中 ${candidates.length} 条报价锚点，取前 5 条按 exp(-geometryDistance) 加权平均。`,
        `尺寸外推：直径、总长、刃长按 1.35 / 0.55 / 0.25 指数修正，并限制在 0.35-4.5。`,
      ],
    }
  }

  return {
    specBasePrice: round2(getFallbackBasePrice(input, precision)),
    matchedAnchors: [],
    source: "fallback",
    bestSimilarity: 0,
    explanation: [
      "未命中可用报价锚点，使用 D6*50 硬质合金普通立铣刀参考价和规格尺寸 fallbackBasePrice。",
      "fallbackBasePrice 已包含材质、涂层、长径比和精度修正，避免重复叠加这些系数。",
    ],
  }
}

export function calculateToolPriceV2(params: {
  spec: ToolQuoteSpec
  quoteAnchors: QuoteAnchor[]
  fIndustry: number
  fProcess: number
  fWorkpiece: number
  mFuture: number
  precision: number
}): ToolPriceV2Result {
  const specPrice = calculateSpecBasePrice(params.spec, params.quoteAnchors, params.precision)
  const supplierFactor = 1
  const categoryFactor = specPrice.source === "fallback" ? 1 : toolKindFactor[params.spec.toolKind]
  const materialAdj = specPrice.source === "fallback" ? 1 : materialFactor[params.spec.material]
  const coatingAdj = specPrice.source === "fallback" ? 1 : coatingFactor[params.spec.coating]
  const geometryFactor = specPrice.source === "fallback" ? 1 : getLongToolFactor(params.spec.diameterMm, params.spec.totalLengthMm)
  const precisionAdj = specPrice.source === "fallback" ? 1 : getPrecisionFactor(params.spec.tolerance, params.precision)
  const rawPrice =
    specPrice.specBasePrice *
    supplierFactor *
    categoryFactor *
    materialAdj *
    coatingAdj *
    geometryFactor *
    precisionAdj *
    params.fIndustry *
    params.fProcess *
    params.fWorkpiece *
    params.mFuture

  const predictedPrice = round2(rawPrice)
  const intervalRate =
    specPrice.source === "exact_quote" ? 0.12 : specPrice.bestSimilarity >= 0.65 ? 0.2 : specPrice.bestSimilarity >= 0.35 ? 0.3 : 0.45

  return {
    predictedPrice,
    lowerPrice: round2(predictedPrice * (1 - intervalRate)),
    upperPrice: round2(predictedPrice * (1 + intervalRate)),
    intervalRate,
    specBasePrice: specPrice.specBasePrice,
    matchedAnchors: specPrice.matchedAnchors,
    formulaVersion: "tool_price_formula_v2",
    explanation: [
      `公式版本：tool_price_formula_v2。`,
      `规格基准价 specBasePrice=${specPrice.specBasePrice}，来源=${specPrice.source}。`,
      `刀型/品类修正=${categoryFactor.toFixed(2)}，材质修正=${materialAdj.toFixed(2)}，涂层修正=${coatingAdj.toFixed(2)}。`,
      `尺寸长径比修正=${geometryFactor.toFixed(2)}，精度修正=${precisionAdj.toFixed(2)}。`,
      `行业/工艺/工件/行情=${params.fIndustry.toFixed(2)} / ${params.fProcess.toFixed(2)} / ${params.fWorkpiece.toFixed(2)} / ${params.mFuture.toFixed(4)}。`,
      ...specPrice.explanation,
    ],
  }
}

export function normalizeQuoteAnchors(rawAnchors: RawQuoteAnchor[]): QuoteAnchor[] {
  return rawAnchors
    .map((anchor) => {
      const parsed = parseToolSpec(anchor.rawSpec, anchor.category)
      const toolKind = anchor.toolKind ?? inferToolKind(anchor.category, anchor.rawSpec)
      const coating = anchor.coating ?? inferCoating(anchor.category)

      return {
        supplier: anchor.supplier,
        category: anchor.category,
        toolKind,
        material: anchor.material ?? "CARBIDE",
        coating,
        diameterMm: parsed.diameterMm,
        fluteLengthMm: parsed.fluteLengthMm,
        totalLengthMm: parsed.totalLengthMm,
        shankDiameterMm: parsed.shankDiameterMm,
        fluteCount: parsed.fluteCount,
        radiusMm: parsed.radiusMm,
        tolerance: parsed.tolerance,
        rawSpec: anchor.rawSpec,
        price: anchor.price,
        priceLabel: anchor.priceLabel,
      }
    })
    .filter((anchor) => Number.isFinite(anchor.price) && anchor.price > 0)
}
