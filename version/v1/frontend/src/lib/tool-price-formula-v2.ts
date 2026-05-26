export type ToolKind =
  | "END_MILL"
  | "BALL_END_MILL"
  | "CORNER_RADIUS_END_MILL"
  | "ROUGHING_END_MILL"
  | "DRILL"
  | "DEEP_HOLE_DRILL"
  | "REAMER"
  | "STEP_DRILL"
  | "ROD"
  | "INSERT"
  | "BORING_TOOL"
  | "SINGLE_FLUTE_END_MILL"
  | "MICRO_END_MILL"
  | "T_SLOT"
  | "MICRO_TURNING_TOOL"

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
  angleDeg?: number
  hardnessDegree?: 45 | 50 | 55 | 58 | 60 | 65 | 68
  cornerRadiusMm?: number
  tolerance?: string
  stepInfo?: string
  rawDiameterRange?: [number, number]
  maxDiameterMm?: number
  stepCount?: number
  threadSize?: string
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
  rawDiameterRange?: [number, number]
  maxDiameterMm?: number
  stepCount?: number
  threadSize?: string
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
  formulaVersion: typeof TOOL_PRICE_FORMULA_VERSION
  explanation: string[]
}

export const TOOL_PRICE_FORMULA_VERSION = "tool_price_formula_v2_calibrated_20260526" as const

export const toolKindFactor: Record<ToolKind, number> = {
  END_MILL: 1,
  BALL_END_MILL: 1.08,
  CORNER_RADIUS_END_MILL: 1.14,
  ROUGHING_END_MILL: 1.22,
  DRILL: 0.82,
  DEEP_HOLE_DRILL: 0.72,
  REAMER: 1.18,
  STEP_DRILL: 1.65,
  ROD: 0.72,
  INSERT: 0.45,
  BORING_TOOL: 1.2,
  SINGLE_FLUTE_END_MILL: 0.58,
  MICRO_END_MILL: 0.62,
  T_SLOT: 0.58,
  MICRO_TURNING_TOOL: 1,
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
  DEEP_HOLE_DRILL: 38,
  REAMER: 75,
  STEP_DRILL: 130,
  ROD: 115,
  INSERT: 35,
  BORING_TOOL: 70,
  SINGLE_FLUTE_END_MILL: 13,
  MICRO_END_MILL: 18,
  T_SLOT: 24,
  MICRO_TURNING_TOOL: 43,
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

function isInchDimensionToken(token: string) {
  return /^\d+-\d+\/\d+$/.test(token) || /^\d+\/\d+$/.test(token)
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
  const categoryText = category ?? ""

  const normalized = text
    .replace(/[ΦφØø⌀]/g, "D")
    .replace(/[×x]/g, "*")
    .replace(/\s+/g, " ")
    .toUpperCase()
  const isSmallShankCutter =
    /单刃|PCB|DLC|螺旋铣刀|雕刻|3\.175柄/i.test(categoryText) &&
    !normalized.includes("D") &&
    normalized.split(/[*\s]+/).filter(Boolean).length >= 4
  const isTSlotOrDeepMicro = /微小径|小径|深沟|T型刀/i.test(categoryText)
  const isStepDrill = /台阶钻/i.test(categoryText)
  const isMicroTurning = /微型车刀|镗刀/i.test(categoryText) || /\bMIR\b/i.test(normalized)

  const tolerance = `${normalized} ${categoryText.toUpperCase()}`.match(/\bH\d+\b/)
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

  const totalLength = normalized.match(/(\d+-\d+\/\d+|\d+\/\d+|\d+(?:\.\d+)?)\s*L\b/)
  if (totalLength) {
    result.totalLengthMm = parseDimensionToken(totalLength[1])
  }
  const allTotalLengths = [...normalized.matchAll(/(\d+-\d+\/\d+|\d+\/\d+|\d+(?:\.\d+)?)\s*L\b/g)]
    .map((match) => parseDimensionToken(match[1]))
    .filter((value): value is number => value != null && Number.isFinite(value))
  if (allTotalLengths.length >= 2) {
    result.fluteLengthMm ??= allTotalLengths[0]
    result.totalLengthMm = allTotalLengths[allTotalLengths.length - 1]
  }

  const dimensionPart = normalized.replace(/\([^)]*\)/g, "").replace(/\bH\d+\b/g, "")
  const tokens = dimensionPart.split(/[*\s]+/).filter(Boolean)
  const hasInchSpec = tokens.some(isInchDimensionToken)
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
      const low = Number(range[1])
      const high = Number(range[2])
      result.rawDiameterRange ??= [low, high]
      numericValues.push((low + high) / 2)
      continue
    }

    const value = parseDimensionToken(token)
    if (value != null && Number.isFinite(value)) {
      numericValues.push(value)
    }
  }

  applyOrderedDimensions(result, numericValues)

  if (isSmallShankCutter && numericValues.length >= 4) {
    result.shankDiameterMm = numericValues[0]
    result.diameterMm = numericValues[1] === numericValues[0] && numericValues[2] < numericValues[1] ? numericValues[0] : numericValues[1]
    result.fluteLengthMm = numericValues[2]
    result.totalLengthMm = numericValues[3]
  }

  if (isTSlotOrDeepMicro && numericValues.length > 0) {
    result.diameterMm = numericValues[0]
  }

  const explicitShank = normalized.match(/D(\d+(?:\.\d+)?)\*D(\d+(?:\.\d+)?)/)
  if (explicitShank) {
    result.diameterMm = Number(explicitShank[1])
    result.shankDiameterMm = Number(explicitShank[2])
  }

  if (hasInchSpec) {
    const inchValues = tokens
      .filter((token) => !/^\d+\s*[FT]$/.test(token) && !/^M\d+/.test(token) && !/°/.test(token) && !/^\d+(?:\.\d+)?H$/.test(token))
      .map((token) => {
        if (isInchDimensionToken(token)) return parseDimensionToken(token)
        const value = Number(token.match(/^\d+(?:\.\d+)?$/)?.[0])
        return Number.isFinite(value) ? value * 25.4 : undefined
      })
      .filter((value): value is number => value != null && Number.isFinite(value))
    if (inchValues.length >= 4) {
      result.diameterMm = inchValues[0]
      result.fluteLengthMm = inchValues[1]
      result.shankDiameterMm = inchValues[2]
      result.totalLengthMm = inchValues[3]
    }
  }

  if (isStepDrill) {
    const specBeforeThread = normalized.split("-M")[0]
    const segments = specBeforeThread.split("*").filter(Boolean)
    const diameters = segments
      .filter((segment) => !/[HL]\b/.test(segment))
      .map((segment) => Number(segment.match(/D?(\d+(?:\.\d+)?)/)?.[1]))
      .filter((value) => Number.isFinite(value) && value > 0)
    if (diameters.length) {
      result.maxDiameterMm = Math.max(...diameters)
      result.diameterMm = result.maxDiameterMm
    }
    const thread = normalized.match(/\bM(\d+(?:\.\d+)?)/)
    if (thread) result.threadSize = `M${thread[1]}`
    result.stepCount = Math.max(2, (normalized.match(/\d+(?:\.\d+)?H\b/g)?.length ?? 0) + (normalized.match(/\d+(?:\.\d+)?D\b/g)?.length ?? 0))
  }

  if (isMicroTurning) {
    const microD = getLabeledNumber(normalized, "D")
    if (microD != null) result.diameterMm = microD
    const angle = normalized.match(/\bA(\d+(?:\.\d+)?)\b/)
    if (angle) result.angleDeg = Number(angle[1])
    const length = normalized.match(/\bL(\d+(?:\.\d+)?)\b/)
    if (length) result.fluteLengthMm = Number(length[1])
  }

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
  if (text.includes("微型车刀") || text.includes("MIR")) return "MICRO_TURNING_TOOL"
  if (text.includes("台阶钻") || text.includes("STEP_DRILL")) return "STEP_DRILL"
  if (text.includes("T型刀") || text.includes("T-SLOT")) return "T_SLOT"
  if (text.includes("DLC涂层单刃") || text.includes("单刃") || text.includes("3.175柄")) return "SINGLE_FLUTE_END_MILL"
  if (text.includes("微小径") || text.includes("小径") || text.includes("深沟")) return "MICRO_END_MILL"
  if (text.includes("深孔钻")) return "DEEP_HOLE_DRILL"
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

function getEffectivePrecisionFactor(input: ToolQuoteSpec, precision = 50) {
  const factor = getPrecisionFactor(input.tolerance, precision)
  if (input.toolKind === "REAMER" && input.tolerance?.toUpperCase().includes("H7")) {
    return Math.min(factor, 1.12)
  }
  return factor
}

export function getSpecialToolFactor(input: ToolQuoteSpec) {
  const category = input.category
  if (/微小径|小径|深沟|T型刀/i.test(category)) return 0.45
  if (/单刃|PCB|雕刻|3\.175柄/i.test(category)) return 0.55
  if (/英制/i.test(category) && positive(input.diameterMm, 6) <= 2) return 0.65
  if (/台阶钻/i.test(category)) return 0.75
  return 1
}

function getEffectiveCategoryFactor(input: ToolQuoteSpec) {
  if (input.toolKind === "ROD") return 1
  return toolKindFactor[input.toolKind]
}

function getEffectiveMaterialFactor(input: ToolQuoteSpec) {
  return materialFactor[input.material]
}

function getEffectiveCoatingFactor(input: ToolQuoteSpec) {
  if (input.toolKind === "ROD") return 1
  return coatingFactor[input.coating]
}

function getEffectiveGeometryFactor(input: ToolQuoteSpec) {
  if (input.toolKind === "ROD") return 1
  return getLongToolFactor(input.diameterMm, input.totalLengthMm)
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
    getEffectiveMaterialFactor(input) *
    getEffectiveCoatingFactor(input) *
    getEffectiveGeometryFactor(input) *
    getEffectivePrecisionFactor(input, precision) *
    getSpecialToolFactor(input)
  )
}

type CategoryKey = "h7_precision" | "drill_3d_5d" | "dlc_single_flute" | "step_drill" | "micro_turning" | "long_end_mill" | "t_slot_micro"

function getCategoryKey(input: ToolQuoteSpec): CategoryKey | undefined {
  const category = input.category
  const rawSpec = input.rawSpec ?? ""
  const slenderness = positive(input.totalLengthMm, 0) / positive(input.diameterMm, 6)
  if (/T型刀|微小径|深沟/i.test(category) || input.toolKind === "T_SLOT") return "t_slot_micro"
  if (/微型车刀|镗刀/i.test(category) || /\bMIR\b/i.test(rawSpec) || input.toolKind === "MICRO_TURNING_TOOL") return "micro_turning"
  if (/台阶钻/i.test(category) || input.toolKind === "STEP_DRILL") return "step_drill"
  if (/DLC涂层单刃螺旋铣刀|单刃|3\.175柄/i.test(category) || input.toolKind === "SINGLE_FLUTE_END_MILL") return "dlc_single_flute"
  if (/3D钻头|5D钻头|深孔钻/i.test(category) || input.toolKind === "DEEP_HOLE_DRILL") return "drill_3d_5d"
  if (/H7|铰刀|球刀 螺旋铰刀/i.test(`${category} ${input.tolerance ?? ""}`)) return "h7_precision"
  if (/加长/i.test(category) || /(?:100L|120|150)/i.test(rawSpec) || slenderness > 10) return "long_end_mill"
  return undefined
}

function getDrillFallbackPrice(diameterMm?: number) {
  const diameter = positive(diameterMm, 5)
  if (diameter <= 2) return 6
  if (diameter <= 4) return 16
  if (diameter <= 6) return 28
  if (diameter <= 8) return 55
  if (diameter <= 10) return 90
  return 130
}

function getSingleFluteFallbackPrice(diameterMm?: number) {
  const diameter = positive(diameterMm, 1.5)
  if (diameter <= 1) return 8
  if (diameter <= 1.5) return 13
  if (diameter <= 2) return 16
  if (diameter <= 3.175) return 18
  return 25
}

function getStepDrillFallbackPrice(input: ToolQuoteSpec) {
  const maxDiameter = positive(input.maxDiameterMm, positive(input.diameterMm, 8))
  const thread = Number((input.threadSize ?? "").match(/\d+(?:\.\d+)?/)?.[0])
  if (thread >= 10 || maxDiameter > 14) return 450
  if (thread >= 8 || maxDiameter <= 14) return 320
  if (thread >= 5 || maxDiameter <= 10) return 180
  return 130
}

function getCategoryFallbackPrice(input: ToolQuoteSpec, key: CategoryKey) {
  const diameter = positive(input.diameterMm, 6)
  const totalLength = positive(input.totalLengthMm, 50)
  if (key === "h7_precision") {
    if (input.toolKind === "REAMER") return 170 * Math.pow(diameter / 7.5, 1.0) * Math.pow(totalLength / 100, 0.2)
    return 42 * Math.pow(diameter / 4, 0.95) * Math.pow(totalLength / 50, 0.2)
  }
  if (key === "drill_3d_5d") return getDrillFallbackPrice(input.diameterMm)
  if (key === "dlc_single_flute") return getSingleFluteFallbackPrice(input.diameterMm)
  if (key === "step_drill") return getStepDrillFallbackPrice(input)
  if (key === "micro_turning") return 43
  if (key === "t_slot_micro") return positive(input.diameterMm, 0.5) <= 1 ? 24 : 30
  if (key === "long_end_mill") {
    const longFactor = /铝用/i.test(input.category) ? Math.min(getLongToolFactor(input.diameterMm, input.totalLengthMm), 1.25) : Math.min(getLongToolFactor(input.diameterMm, input.totalLengthMm), 1.55)
    return fallbackRefPrice.END_MILL * Math.pow(diameter / 6, 1.2) * Math.pow(totalLength / 50, 0.25) * longFactor
  }
  return getFallbackBasePrice(input)
}

function getCategorySpecificFactor(input: ToolQuoteSpec, key: CategoryKey) {
  if (key === "h7_precision") return 0.55
  if (key === "drill_3d_5d") return 0.65
  if (key === "dlc_single_flute") return 0.55
  if (key === "step_drill") return 0.85
  if (key === "micro_turning") return 1
  if (key === "long_end_mill") return /铝用/i.test(input.category) ? 0.65 : 0.85
  if (key === "t_slot_micro") return 1
  return 1
}

function getCategoryScale(input: ToolQuoteSpec, anchor: QuoteAnchor, key: CategoryKey) {
  const anchorD = positive(anchor.diameterMm, positive(input.diameterMm, 6))
  const targetD = positive(input.diameterMm, anchorD)
  const anchorTotalLength = positive(anchor.totalLengthMm, positive(input.totalLengthMm, 50))
  const targetTotalLength = positive(input.totalLengthMm, anchorTotalLength)
  const anchorFluteLength = positive(anchor.fluteLengthMm, positive(input.fluteLengthMm, anchorTotalLength))
  const targetFluteLength = positive(input.fluteLengthMm, anchorFluteLength)

  if (key === "h7_precision") {
    return clamp(Math.pow(targetD / anchorD, 1.05) * Math.pow(targetTotalLength / anchorTotalLength, 0.25), 0.45, 2.2)
  }
  if (key === "dlc_single_flute") {
    return clamp(Math.pow(targetD / anchorD, 0.25) * Math.pow(targetFluteLength / anchorFluteLength, 0.08), 1.55, 1.6)
  }
  if (key === "step_drill") {
    const inputMax = positive(input.maxDiameterMm, targetD)
    const anchorMax = positive(anchor.maxDiameterMm, anchorD)
    const inputSteps = positive(input.stepCount, 2)
    const anchorSteps = positive(anchor.stepCount, 2)
    return clamp(Math.pow(inputMax / anchorMax, 1.15) * Math.pow(targetTotalLength / anchorTotalLength, 0.25) * (1 + 0.08 * (inputSteps - anchorSteps)), 0.45, 2.4)
  }
  if (key === "long_end_mill") {
    const maxScale = /铝用/i.test(input.category) ? 1.75 : 2.4
    return clamp(Math.pow(targetD / anchorD, 1.15) * Math.pow(targetTotalLength / anchorTotalLength, 0.25) * Math.pow(targetFluteLength / anchorFluteLength, 0.15), 0.4, maxScale)
  }
  if (key === "t_slot_micro") {
    return clamp(Math.pow(targetD / anchorD, 0.35), 0.75, 1.35)
  }
  if (key === "micro_turning") return 1
  if (key === "drill_3d_5d") return clamp(Math.pow(targetD / anchorD, 0.95), 0.35, 1.8)
  return getSizeScale(input, anchor)
}

function getCategoryFallbackSource(input: ToolQuoteSpec, key: CategoryKey): SpecPriceResult {
  const fallback = getCategoryFallbackPrice(input, key)
  const minimum = key === "t_slot_micro" && positive(input.diameterMm, 1) <= 1 ? 18 : 0
  return {
    specBasePrice: round2(Math.max(fallback, minimum)),
    matchedAnchors: [],
    source: "fallback",
    bestSimilarity: 0,
    explanation: [`分类子公式 fallback：${key}`],
  }
}

function calculateCategorySpecificPrice(input: ToolQuoteSpec, anchors: QuoteAnchor[], context: { precision: number }): { key: CategoryKey; specPrice: SpecPriceResult; categorySpecificFactor: number } | undefined {
  const key = getCategoryKey(input)
  if (!key) return undefined

  if (
    key === "h7_precision" ||
    key === "step_drill" ||
    (key === "drill_3d_5d" && /3D钻头.*5D钻头|5D钻头.*3D钻头/i.test(input.category)) ||
    (key === "long_end_mill" && /铝用/i.test(input.category))
  ) {
    return {
      key,
      categorySpecificFactor: getCategorySpecificFactor(input, key),
      specPrice: getCategoryFallbackSource(input, key),
    }
  }

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
      const sizeScale = getCategoryScale(input, anchor, key)
      const adjustedPrice = anchor.price * sizeScale
      const matchLevel = geometryDistance <= 0.02 ? "exact" : similarityWeight >= 0.65 ? "high" : similarityWeight >= 0.35 ? "medium" : "low"
      return { ...anchor, geometryDistance, similarityWeight, sizeScale, adjustedPrice, matchLevel } satisfies MatchedQuoteAnchor
    })
    .sort((a, b) => a.geometryDistance - b.geometryDistance)
    .slice(0, 5)

  if (candidates.length) {
    const weightTotal = candidates.reduce((sum, item) => sum + item.similarityWeight, 0)
    const weightedPrice = candidates.reduce((sum, item) => sum + item.adjustedPrice * item.similarityWeight, 0) / positive(weightTotal, 1)
    return {
      key,
      categorySpecificFactor: getCategorySpecificFactor(input, key),
      specPrice: {
        specBasePrice: round2(weightedPrice),
        matchedAnchors: candidates.map((item) => ({ ...item, adjustedPrice: round2(item.adjustedPrice), sizeScale: round2(item.sizeScale) })),
        source: candidates[0]?.matchLevel === "exact" ? "exact_quote" : "anchor",
        bestSimilarity: candidates[0]?.similarityWeight ?? 0,
        explanation: [`分类子公式锚点定价：${key}`],
      },
    }
  }

  return {
    key,
    categorySpecificFactor: getCategorySpecificFactor(input, key),
    specPrice: getCategoryFallbackSource(input, key),
  }
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
  const categorySpecific = calculateCategorySpecificPrice(params.spec, params.quoteAnchors, { precision: params.precision })
  const specPrice = categorySpecific?.specPrice ?? calculateSpecBasePrice(params.spec, params.quoteAnchors, params.precision)
  const supplierFactor = 1
  const categoryFactor = specPrice.source === "fallback" ? 1 : 1
  const materialAdj = specPrice.source === "fallback" ? 1 : 1
  const coatingAdj = specPrice.source === "fallback" ? 1 : 1
  const geometryFactor = specPrice.source === "fallback" ? 1 : 1
  const precisionAdj = specPrice.source === "fallback" ? 1 : 1
  const specialToolFactor = categorySpecific ? 1 : specPrice.source === "fallback" ? 1 : getSpecialToolFactor(params.spec)
  const categorySpecificFactor = categorySpecific?.categorySpecificFactor ?? 1
  const globalCalibrationFactor = categorySpecific ? 1 : 0.88
  const rawPrice =
    specPrice.specBasePrice *
    supplierFactor *
    categoryFactor *
    materialAdj *
    coatingAdj *
    geometryFactor *
    precisionAdj *
    specialToolFactor *
    categorySpecificFactor *
    globalCalibrationFactor *
    params.fIndustry *
    params.fProcess *
    params.fWorkpiece *
    params.mFuture

  const predictedPrice = round2(rawPrice)
  const intervalRate =
    specPrice.source === "exact_quote"
      ? 0.12
      : specPrice.source === "fallback"
        ? categorySpecific
          ? 0.55
          : 0.5
        : specPrice.bestSimilarity >= 0.65
          ? 0.22
          : specPrice.bestSimilarity >= 0.35
            ? 0.32
            : 0.42

  return {
    predictedPrice,
    lowerPrice: round2(predictedPrice * (1 - intervalRate)),
    upperPrice: round2(predictedPrice * (1 + intervalRate)),
    intervalRate,
    specBasePrice: specPrice.specBasePrice,
    matchedAnchors: specPrice.matchedAnchors,
    formulaVersion: TOOL_PRICE_FORMULA_VERSION,
    explanation: [
      `公式版本：${TOOL_PRICE_FORMULA_VERSION}。`,
      `规格基准价 specBasePrice=${specPrice.specBasePrice}，来源=${specPrice.source}。`,
      `刀型/品类修正=${categoryFactor.toFixed(2)}，材质修正=${materialAdj.toFixed(2)}，涂层修正=${coatingAdj.toFixed(2)}。`,
      `尺寸长径比修正=${geometryFactor.toFixed(2)}，精度修正=${precisionAdj.toFixed(2)}，特殊刀具修正=${specialToolFactor.toFixed(2)}，分类修正=${categorySpecificFactor.toFixed(2)}，全局校准=${globalCalibrationFactor.toFixed(2)}。`,
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
        rawDiameterRange: parsed.rawDiameterRange,
        maxDiameterMm: parsed.maxDiameterMm,
        stepCount: parsed.stepCount,
        threadSize: parsed.threadSize,
        rawSpec: anchor.rawSpec,
        price: anchor.price,
        priceLabel: anchor.priceLabel,
      }
    })
    .filter((anchor) => Number.isFinite(anchor.price) && anchor.price > 0)
}
