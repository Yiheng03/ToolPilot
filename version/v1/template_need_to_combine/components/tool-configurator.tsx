"use client"

import { useState } from "react"
import { AlertCircle, CheckCircle2, CircleDollarSign, Cog, Factory, Layers, Loader2, Ruler, Sparkles, Wrench } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"

type MetalCode = "CU" | "AL" | "ZN" | "NI" | "SN" | "PB" | "CO" | "IRON_ORE"
type Horizon = 7 | 30 | 90

interface MarketForecastRow {
  horizon_day: number
  metal_code: string
  base_price?: number | null
  final_predicted_price?: number | null
  predicted_price_p50?: number | null
  forecast_date?: string | null
  model_reliability_level?: string | null
}

interface FactorSnapshot {
  horizon: Horizon
  predictedPrice: number
  lowerPrice: number
  upperPrice: number
  priceChangePct: number
  mFuture: number
  rG: number
  rQ: number
  betaG: number
  eta: number
  fIndustry: number
  fProcess: number
  fWorkpiece: number
  metalIndices: Record<MetalCode, number>
  forecastDate?: string | null
}

interface ToolRecommendation {
  toolName: string
  toolType: string
  toolMaterialCode: string
  toolTypeCode: string
  material: string
  coating: string
  dimensions: {
    diameter: string
    length: string
    shankDiameter: string
  }
  specs: string[]
  basePrice: number
  price: {
    unit: number
    bulk: number
    currency: string
  }
  performance: {
    durability: number
    precision: number
    efficiency: number
  }
  suitability: number
  forecasts: FactorSnapshot[]
  warning?: string
}

const METALS: MetalCode[] = ["CU", "AL", "ZN", "NI", "SN", "PB", "CO", "IRON_ORE"]
const HORIZONS: Horizon[] = [7, 30, 90]

const industries = [
  { value: "AUTOMOTIVE", label: "汽车制造", icon: "🚗" },
  { value: "AEROSPACE", label: "航空航天", icon: "✈️" },
  { value: "GENERAL_MACHINERY", label: "通用机械", icon: "⚙️" },
  { value: "MOLD", label: "模具加工", icon: "🔧" },
  { value: "ELECTRONICS", label: "电子制造", icon: "💻" },
  { value: "MEDICAL", label: "医疗器械", icon: "🏥" },
  { value: "ENERGY", label: "能源装备", icon: "⚡" },
  { value: "SHIPBUILDING", label: "船舶制造", icon: "🚢" },
]

const scenarios = [
  { value: "TURNING", label: "车削加工" },
  { value: "MILLING", label: "铣削加工" },
  { value: "DRILLING", label: "钻削加工" },
  { value: "BORING", label: "镗削加工" },
  { value: "GRINDING", label: "磨削加工" },
  { value: "THREADING", label: "螺纹加工" },
]

const materials = [
  { value: "CARBON_STEEL", label: "普通钢" },
  { value: "STAINLESS_STEEL", label: "不锈钢" },
  { value: "ALUMINUM_ALLOY", label: "铝合金" },
  { value: "TITANIUM_ALLOY", label: "钛合金" },
  { value: "CAST_IRON", label: "铸铁" },
  { value: "COMPOSITE", label: "复合材料" },
]

const industryFactor: Record<string, number> = {
  AUTOMOTIVE: 1,
  AEROSPACE: 1.35,
  GENERAL_MACHINERY: 1,
  MOLD: 1.2,
  ELECTRONICS: 1.12,
  MEDICAL: 1.4,
  ENERGY: 1.25,
  SHIPBUILDING: 1.1,
}

const processFactor: Record<string, number> = {
  TURNING: 1,
  MILLING: 1.18,
  DRILLING: 1.1,
  BORING: 1.25,
  GRINDING: 1.12,
  THREADING: 1.28,
}

const workpieceFactor: Record<string, number> = {
  CARBON_STEEL: 1,
  STAINLESS_STEEL: 1.12,
  ALUMINUM_ALLOY: 0.95,
  TITANIUM_ALLOY: 1.35,
  CAST_IRON: 1.08,
  COMPOSITE: 1.3,
}

const industryEta: Record<string, number> = {
  AUTOMOTIVE: 0.08,
  AEROSPACE: 0.15,
  GENERAL_MACHINERY: 0.06,
  MOLD: 0.1,
  ELECTRONICS: 0.08,
  MEDICAL: 0.12,
  ENERGY: 0.12,
  SHIPBUILDING: 0.1,
}

function fmtMoney(value: number) {
  return value.toLocaleString("zh-CN", { maximumFractionDigits: 2, minimumFractionDigits: 2 })
}

function fmtFactor(value: number) {
  return value.toFixed(4)
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value))
}

function weighted(indices: Record<MetalCode, number>, weights: Partial<Record<MetalCode, number>>) {
  return Object.entries(weights).reduce((sum, [metal, weight]) => sum + indices[metal as MetalCode] * Number(weight), 0)
}

function getToolMaterialIndex(toolMaterial: string, indices: Record<MetalCode, number>) {
  if (toolMaterial === "CARBIDE") {
    return weighted(indices, { CO: 0.55, NI: 0.2, IRON_ORE: 0.15, AL: 0.05, CU: 0.05 })
  }
  if (toolMaterial === "HSS") {
    return weighted(indices, { IRON_ORE: 0.55, NI: 0.15, CO: 0.15, CU: 0.05, AL: 0.05, ZN: 0.03, SN: 0.02 })
  }
  if (["CERAMIC", "CBN", "PCD"].includes(toolMaterial)) {
    return weighted(indices, { IRON_ORE: 0.3, AL: 0.2, CU: 0.2, NI: 0.15, CO: 0.15 })
  }
  if (toolMaterial === "STEEL_HOLDER") {
    return weighted(indices, { IRON_ORE: 0.65, NI: 0.15, CU: 0.1, AL: 0.05, ZN: 0.05 })
  }
  return 1
}

function getWorkpieceMarketIndex(workpiece: string, indices: Record<MetalCode, number>) {
  if (workpiece === "CARBON_STEEL") {
    return weighted(indices, { IRON_ORE: 0.75, NI: 0.1, CO: 0.05, ZN: 0.05, CU: 0.05 })
  }
  if (workpiece === "STAINLESS_STEEL") {
    return weighted(indices, { NI: 0.55, IRON_ORE: 0.25, CO: 0.1, CU: 0.05, SN: 0.05 })
  }
  if (workpiece === "ALUMINUM_ALLOY") {
    return weighted(indices, { AL: 0.7, CU: 0.15, ZN: 0.1, SN: 0.05 })
  }
  if (workpiece === "TITANIUM_ALLOY") {
    return weighted(indices, { NI: 0.35, CO: 0.3, AL: 0.2, IRON_ORE: 0.1, CU: 0.05 })
  }
  if (workpiece === "CAST_IRON") {
    return weighted(indices, { IRON_ORE: 0.8, CO: 0.05, NI: 0.05, ZN: 0.05, CU: 0.05 })
  }
  if (workpiece === "COMPOSITE") {
    return weighted(indices, { AL: 0.25, CU: 0.2, NI: 0.2, CO: 0.2, IRON_ORE: 0.15 })
  }
  return 1
}

function getBetaG(toolMaterial: string, toolType: string) {
  const exact: Record<string, number> = {
    "CARBIDE:END_MILL": 0.28,
    "CARBIDE:DRILL": 0.28,
    "CARBIDE:INSERT": 0.35,
    "CARBIDE:REAMER": 0.25,
    "CARBIDE:BORING_TOOL": 0.25,
    "HSS:DRILL": 0.2,
    "HSS:TAP": 0.22,
    "HSS:REAMER": 0.2,
    "HSS:END_MILL": 0.2,
  }
  const matched = exact[`${toolMaterial}:${toolType}`]
  if (matched != null) return matched
  if (toolMaterial === "CARBIDE") return 0.28
  if (toolMaterial === "HSS") return 0.2
  if (["CERAMIC", "CBN", "PCD"].includes(toolMaterial)) return 0.08
  if (toolMaterial === "STEEL_HOLDER" || toolType === "HOLDER") return 0.35
  return 0.2
}

function buildMetalIndices(rows: MarketForecastRow[], horizon: Horizon) {
  const selected = rows.filter((row) => Number(row.horizon_day) === horizon)
  const indices = Object.fromEntries(METALS.map((metal) => [metal, 1])) as Record<MetalCode, number>
  const forecastDate = selected.find((row) => row.forecast_date)?.forecast_date

  for (const metal of METALS) {
    const row = selected.find((item) => item.metal_code === metal)
    const current = Number(row?.base_price)
    const forecast = Number(row?.final_predicted_price ?? row?.predicted_price_p50)
    indices[metal] = Number.isFinite(current) && current > 0 && Number.isFinite(forecast) ? forecast / current : 1
  }

  return { indices, forecastDate }
}

function makeBaseRecommendation(industry: string, processType: string, workpieceMaterial: string, precision: number): Omit<ToolRecommendation, "forecasts" | "warning"> {
  const isTitaniumAerospace = industry === "AEROSPACE" && workpieceMaterial === "TITANIUM_ALLOY"
  const isAutomotiveTurning = industry === "AUTOMOTIVE" && processType === "TURNING"
  const isMoldMilling = industry === "MOLD" && processType === "MILLING"

  const base: Omit<ToolRecommendation, "forecasts" | "warning"> = {
    toolName: "高性能硬质合金立铣刀",
    toolType: "整体硬质合金铣刀",
    toolMaterialCode: "CARBIDE",
    toolTypeCode: "END_MILL",
    material: "超细颗粒硬质合金 (WC-Co)",
    coating: "AlTiN 纳米复合涂层",
    dimensions: {
      diameter: "Ø12mm",
      length: "75mm",
      shankDiameter: "Ø12mm",
    },
    specs: ["刃数: 4刃", "螺旋角: 45°", "刃长: 30mm", "总长: 75mm"],
    basePrice: 280,
    price: {
      unit: 280,
      bulk: 238,
      currency: "CNY",
    },
    performance: {
      durability: 85,
      precision: 92,
      efficiency: 88,
    },
    suitability: 95,
  }

  if (isTitaniumAerospace) {
    base.toolName = "钛合金专用高效铣刀"
    base.coating = "TiAlN + WC/C 多层复合涂层"
    base.basePrice = 450
    base.price = { unit: 450, bulk: 382, currency: "CNY" }
    base.performance = { durability: 78, precision: 95, efficiency: 82 }
    base.suitability = 98
  } else if (isAutomotiveTurning) {
    base.toolName = "汽车零部件精密车刀片"
    base.toolType = "可转位车刀片 CNMG"
    base.toolMaterialCode = "CERAMIC"
    base.toolTypeCode = "INSERT"
    base.material = "陶瓷基复合材料"
    base.coating = "TiN 耐磨涂层"
    base.dimensions = { diameter: "16mm", length: "16mm", shankDiameter: "20mm 刀杆" }
    base.basePrice = 45
    base.price = { unit: 45, bulk: 38, currency: "CNY" }
    base.suitability = 96
  } else if (isMoldMilling) {
    base.toolName = "模具专用球头铣刀"
    base.toolType = "整体硬质合金球头铣刀"
    base.coating = "DLC 超硬涂层"
    base.dimensions = { diameter: "R3mm", length: "100mm", shankDiameter: "Ø6mm" }
    base.specs = ["刃数: 2刃", "球头精度: ±0.005mm", "表面粗糙度: Ra0.2", "适用 HRC65 以下"]
    base.basePrice = 320
    base.price = { unit: 320, bulk: 272, currency: "CNY" }
    base.performance = { durability: 80, precision: 98, efficiency: 75 }
    base.suitability = 97
  }

  if (precision > 75) {
    base.performance.precision = Math.min(99, base.performance.precision + 5)
    base.basePrice = Math.round(base.basePrice * 1.2)
    base.price = {
      ...base.price,
      unit: Math.round(base.price.unit * 1.2),
      bulk: Math.round(base.price.bulk * 1.2),
    }
  }

  return base
}

function calculateForecasts(
  recommendation: Omit<ToolRecommendation, "forecasts" | "warning">,
  rows: MarketForecastRow[],
  industry: string,
  processType: string,
  workpieceMaterial: string,
) {
  const fIndustry = industryFactor[industry] ?? 1
  const fProcess = processFactor[processType] ?? 1
  const fWorkpiece = workpieceFactor[workpieceMaterial] ?? 1
  const betaG = getBetaG(recommendation.toolMaterialCode, recommendation.toolTypeCode)
  const eta = industryEta[industry] ?? 0.08

  return HORIZONS.map((horizon) => {
    const { indices, forecastDate } = buildMetalIndices(rows, horizon)
    const rG = getToolMaterialIndex(recommendation.toolMaterialCode, indices)
    const rQ = getWorkpieceMarketIndex(workpieceMaterial, indices)
    const mFuture = clamp(1 + betaG * (rG - 1) + eta * (rQ - 1), 0.85, 1.15)
    const predictedPrice = recommendation.basePrice * fIndustry * fProcess * fWorkpiece * mFuture
    const rounded = Number(predictedPrice.toFixed(2))

    return {
      horizon,
      predictedPrice: rounded,
      lowerPrice: Number((rounded * 0.7).toFixed(2)),
      upperPrice: Number((rounded * 1.3).toFixed(2)),
      priceChangePct: Number((((rounded / recommendation.basePrice) - 1) * 100).toFixed(2)),
      mFuture,
      rG,
      rQ,
      betaG,
      eta,
      fIndustry,
      fProcess,
      fWorkpiece,
      metalIndices: indices,
      forecastDate,
    }
  })
}

export function ToolConfigurator() {
  const [industry, setIndustry] = useState("")
  const [scenario, setScenario] = useState("")
  const [workpieceMaterial, setWorkpieceMaterial] = useState("")
  const [precision, setPrecision] = useState([50])
  const [selectedHorizon, setSelectedHorizon] = useState<Horizon>(30)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [recommendation, setRecommendation] = useState<ToolRecommendation | null>(null)

  const handleGenerate = async () => {
    if (!industry || !scenario || !workpieceMaterial) return

    setIsLoading(true)
    setError("")

    try {
      const response = await fetch("/api/market/production-forecasts", { cache: "no-store" })
      if (!response.ok) {
        throw new Error(`production-forecasts ${response.status}`)
      }

      const rows = (await response.json()) as MarketForecastRow[]
      const baseRec = makeBaseRecommendation(industry, scenario, workpieceMaterial, precision[0])
      const forecasts = calculateForecasts(baseRec, rows, industry, scenario, workpieceMaterial)

      setRecommendation({
        ...baseRec,
        forecasts,
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : "行情预测接口调用失败")
      setRecommendation(null)
    } finally {
      setIsLoading(false)
    }
  }

  const isFormComplete = Boolean(industry && scenario && workpieceMaterial)
  const activeForecast = recommendation?.forecasts.find((item) => item.horizon === selectedHorizon)
  const materialLabel = materials.find((item) => item.value === workpieceMaterial)?.label || "--"
  const industryLabel = industries.find((item) => item.value === industry)?.label || "--"
  const scenarioLabel = scenarios.find((item) => item.value === scenario)?.label || "--"

  return (
    <section id="configurator" className="py-20 bg-muted/30">
      <div className="container mx-auto px-4">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">智能刀具配置器</h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            选择行业、使用场景和工件材料，系统将接入金属市场预测并生成未来刀具报价区间。
          </p>
        </div>

        <div className="grid lg:grid-cols-2 gap-8 max-w-6xl mx-auto">
          <Card className="shadow-lg border-border/50">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Cog className="h-5 w-5 text-primary" />
                配置参数
              </CardTitle>
              <CardDescription>以下选项会参与行业、工艺、工件材料和市场预测修正。</CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-2">
                <Label className="flex items-center gap-2">
                  <Factory className="h-4 w-4 text-muted-foreground" />
                  所属行业
                </Label>
                <select
                  className="border-input bg-background text-foreground h-10 w-full rounded-md border px-3 py-2 text-sm outline-none transition-[color,box-shadow] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
                  value={industry}
                  onChange={(event) => setIndustry(event.target.value)}
                >
                  <option value="">请选择您的行业</option>
                  {industries.map((ind) => (
                    <option key={ind.value} value={ind.value}>
                      {ind.icon} {ind.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-2">
                <Label className="flex items-center gap-2">
                  <Wrench className="h-4 w-4 text-muted-foreground" />
                  使用场景
                </Label>
                <select
                  className="border-input bg-background text-foreground h-10 w-full rounded-md border px-3 py-2 text-sm outline-none transition-[color,box-shadow] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
                  value={scenario}
                  onChange={(event) => setScenario(event.target.value)}
                >
                  <option value="">请选择加工类型</option>
                  {scenarios.map((sc) => (
                    <option key={sc.value} value={sc.value}>
                      {sc.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-2">
                <Label className="flex items-center gap-2">
                  <Layers className="h-4 w-4 text-muted-foreground" />
                  工件材料
                </Label>
                <select
                  className="border-input bg-background text-foreground h-10 w-full rounded-md border px-3 py-2 text-sm outline-none transition-[color,box-shadow] focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
                  value={workpieceMaterial}
                  onChange={(event) => setWorkpieceMaterial(event.target.value)}
                >
                  <option value="">请选择工件材料</option>
                  {materials.map((mat) => (
                    <option key={mat.value} value={mat.value}>
                      {mat.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="space-y-4">
                <Label className="flex items-center justify-between">
                  <span className="flex items-center gap-2">
                    <Ruler className="h-4 w-4 text-muted-foreground" />
                    精度要求
                  </span>
                  <span className="text-sm text-muted-foreground">
                    {precision[0] < 33 ? "一般精度" : precision[0] < 66 ? "中等精度" : "高精度"}
                  </span>
                </Label>
                <Slider value={precision} onValueChange={setPrecision} max={100} step={1} className="w-full" />
              </div>

              <Separator />

              <Button
                className="w-full bg-gradient-to-r from-primary to-accent hover:opacity-90"
                size="lg"
                onClick={handleGenerate}
                disabled={!isFormComplete || isLoading}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    正在读取行情预测...
                  </>
                ) : (
                  <>
                    <Sparkles className="mr-2 h-5 w-5" />
                    生成智能推荐
                  </>
                )}
              </Button>

              {!isFormComplete && (
                <p className="text-sm text-muted-foreground text-center flex items-center justify-center gap-1">
                  <AlertCircle className="h-4 w-4" />
                  请完成所有配置项
                </p>
              )}

              {error && (
                <p className="text-sm text-destructive text-center flex items-center justify-center gap-1">
                  <AlertCircle className="h-4 w-4" />
                  行情预测 API 调用失败：{error}
                </p>
              )}
            </CardContent>
          </Card>

          <Card className="shadow-lg border-border/50">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Sparkles className="h-5 w-5 text-accent" />
                推荐方案
              </CardTitle>
              <CardDescription>基于市场预测和 tool_price_formula_v1 的刀具报价结果。</CardDescription>
            </CardHeader>
            <CardContent>
              {recommendation && activeForecast ? (
                <div className="space-y-6">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <h3 className="text-xl font-bold text-foreground">{recommendation.toolName}</h3>
                      <p className="text-sm text-muted-foreground">{recommendation.toolType}</p>
                    </div>
                    <Badge className="bg-green-500/10 text-green-600 hover:bg-green-500/20">
                      <CheckCircle2 className="h-3 w-3 mr-1" />
                      匹配度 {recommendation.suitability}%
                    </Badge>
                  </div>

                  <Separator />

                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <p className="text-xs text-muted-foreground uppercase tracking-wider">基体材料</p>
                      <p className="text-sm font-medium">{recommendation.material}</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-xs text-muted-foreground uppercase tracking-wider">涂层类型</p>
                      <p className="text-sm font-medium">{recommendation.coating}</p>
                    </div>
                  </div>

                  <div className="p-4 rounded-lg bg-muted/50">
                    <p className="text-xs text-muted-foreground uppercase tracking-wider mb-3 flex items-center gap-1">
                      <Ruler className="h-3 w-3" />
                      尺寸规格
                    </p>
                    <div className="grid grid-cols-3 gap-4">
                      <div className="text-center">
                        <p className="text-lg font-bold text-primary">{recommendation.dimensions.diameter}</p>
                        <p className="text-xs text-muted-foreground">直径</p>
                      </div>
                      <div className="text-center">
                        <p className="text-lg font-bold text-primary">{recommendation.dimensions.length}</p>
                        <p className="text-xs text-muted-foreground">全长</p>
                      </div>
                      <div className="text-center">
                        <p className="text-lg font-bold text-primary">{recommendation.dimensions.shankDiameter}</p>
                        <p className="text-xs text-muted-foreground">柄径</p>
                      </div>
                    </div>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    {recommendation.specs.map((spec) => (
                      <Badge key={spec} variant="secondary" className="text-xs">
                        {spec}
                      </Badge>
                    ))}
                    <p className="text-xs text-muted-foreground w-full mt-1">未选定产品规格，使用默认规格进行计算，详细规格点击获得详细报价</p>
                  </div>

                  <div className="flex gap-2">
                    {HORIZONS.map((horizon) => (
                      <Button
                        key={horizon}
                        type="button"
                        size="sm"
                        variant={selectedHorizon === horizon ? "default" : "outline"}
                        onClick={() => setSelectedHorizon(horizon)}
                      >
                        {horizon}天
                      </Button>
                    ))}
                  </div>

                  <div className="grid grid-cols-2 gap-3 text-sm">
                    <div className="rounded-lg border border-border/60 p-3">
                      <p className="text-xs text-muted-foreground">工件材料市场指数 R_q</p>
                      <p className="mt-1 font-semibold">{fmtFactor(activeForecast.rQ)}</p>
                    </div>
                    <div className="rounded-lg border border-border/60 p-3">
                      <p className="text-xs text-muted-foreground">金属行情修正 M_future</p>
                      <p className="mt-1 font-semibold">{fmtFactor(activeForecast.mFuture)}</p>
                    </div>
                    <div className="rounded-lg border border-border/60 p-3">
                      <p className="text-xs text-muted-foreground">行业 / 工艺 / 工件</p>
                      <p className="mt-1 font-semibold">
                        {activeForecast.fIndustry.toFixed(2)} / {activeForecast.fProcess.toFixed(2)} / {activeForecast.fWorkpiece.toFixed(2)}
                      </p>
                    </div>
                    <div className="rounded-lg border border-border/60 p-3">
                      <p className="text-xs text-muted-foreground">基体材料指数 R_g</p>
                      <p className="mt-1 font-semibold">{fmtFactor(activeForecast.rG)}</p>
                    </div>
                  </div>

                  <Separator />

                  <div className="space-y-2 text-sm text-muted-foreground">
                    <p>
                      当前组合：{industryLabel} / {scenarioLabel} / {materialLabel}。
                    </p>
                    <p>
                      行情 API：/api/market/production-forecasts，基准日 {activeForecast.forecastDate || "--"}，当前展示 {selectedHorizon} 天预测。
                    </p>
                  </div>

                  <div className="flex items-end justify-between gap-4">
                    <div>
                      <p className="text-xs text-muted-foreground uppercase tracking-wider flex items-center gap-1">
                        <CircleDollarSign className="h-3 w-3" />
                        预测报价
                      </p>
                      <div className="flex items-baseline gap-2 mt-1">
                        <span className="text-2xl font-bold text-primary">¥{fmtMoney(activeForecast.predictedPrice)}</span>
                        <span className="text-sm text-muted-foreground">/支</span>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        合理区间: ¥{fmtMoney(activeForecast.lowerPrice)} - ¥{fmtMoney(activeForecast.upperPrice)}
                      </p>
                    </div>
                    <Button className="bg-gradient-to-r from-primary to-accent hover:opacity-90">获取详细报价</Button>
                  </div>
                </div>
              ) : (
                <div className="flex flex-col items-center justify-center h-[400px] text-center">
                  <div className="w-20 h-20 rounded-full bg-muted/50 flex items-center justify-center mb-4">
                    <Wrench className="h-10 w-10 text-muted-foreground/50" />
                  </div>
                  <h3 className="text-lg font-medium text-muted-foreground mb-2">等待配置</h3>
                  <p className="text-sm text-muted-foreground max-w-xs">
                    请在左侧填写配置参数，系统将读取金属预测并生成刀具推荐方案。
                  </p>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </section>
  )
}
