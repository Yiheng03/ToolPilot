// ─── Types ───────────────────────────────────────────────

export interface MetalRanking {
  metal_code: string;
  metal_name: string;
  base_price: number | null;
  final_predicted_return: number | null;
  final_predicted_price: number | null;
  relative_strength_rank: number | null;
  procurement_signal: string | null;
}

export interface ForecastRow {
  forecast_date: string;
  horizon_day: number;
  metal_code: string;
  metal_name: string;
  base_price: number | null;
  final_predicted_return: number | null;
  final_predicted_price: number | null;
  predicted_return_p10: number | null;
  predicted_return_p50: number | null;
  predicted_return_p90: number | null;
  predicted_price_p10: number | null;
  predicted_price_p50: number | null;
  predicted_price_p90: number | null;
  relative_strength_rank: number | null;
  volatility_level: string | null;
  risk_level: string | null;
  procurement_signal: string | null;
  procurement_advice: string | null;
  key_drivers: {
    base_lgb?: number | null;
    market_factor?: number | null;
    catboost_excess?: number | null;
    pair_adjustment?: number | null;
  } | null;
  data_quality_score: number | null;
  model_reliability_level: string | null;
  forecast_target_date: string | null;
  reliability_score: number | null;
  reliability_score_note: string | null;
  interval_judgement: string | null;
  interval_width: number | null;
  reliability_score_breakdown: {
    data_quality: number | null;
    direction_interval: number | null;
    interval_width: number | null;
    median_signal: number | null;
  } | null;
  reliability_score_reasons: string[] | null;
}

export interface CurrentSignal {
  final_predicted_return_30d: number | null;
  final_predicted_price_30d: number | null;
  relative_strength_rank: number | null;
  risk_level: string | null;
  procurement_signal: string | null;
  procurement_advice: string | null;
  model_reliability_level: string | null;
  reliability_score: number | null;
  reliability_score_note: string | null;
  interval_judgement: string | null;
  interval_width: number | null;
  reliability_score_breakdown: {
    data_quality: number | null;
    direction_interval: number | null;
    interval_width: number | null;
    median_signal: number | null;
  } | null;
  reliability_score_reasons: string[] | null;
  volatility_level: string | null;
}

export interface HistoryRow {
  date: string | null;
  price_date?: string | null;
  actual_price: number | null;
}

export interface DetailResponse {
  metal_code: string;
  metal_name: string | null;
  forecast_date: string | null;
  base_price: number | null;
  current_signal: CurrentSignal;
  history: HistoryRow[];
  forecasts: ForecastRow[];
}

export interface ChartPoint {
  date: string;
  actualPrice?: number;
  forecastPrice?: number;
  forecastLow?: number;
  forecastHigh?: number;
  pointType: "history" | "forecast_start" | "forecast";
  label?: string;
  horizonDay?: number;
  predictedReturn?: number | null;
  reliabilityScore?: number | null;
  reliabilityNote?: string | null;
}

export interface MarketState {
  ranking: MetalRanking[];
  detail: DetailResponse | null;
  selectedMetal: string;
  forecastDateTouched: boolean;
  historyRangeTouched: boolean;
}

// ─── Metal name map ─────────────────────────────────────

export const METAL_NAMES: Record<string, string> = {
  CU: "铜",
  AL: "铝",
  NI: "镍",
  CO: "钴",
  ZN: "锌",
  SN: "锡",
  PB: "铅",
  IRON_ORE: "铁矿石",
};

// ─── Formatting ─────────────────────────────────────────

export function fmtNum(value: unknown): string {
  const n = Number(value);
  if (value == null || Number.isNaN(n)) return "--";
  return n.toLocaleString("zh-CN", { maximumFractionDigits: 2 });
}

export function fmtMoney(value: unknown): string {
  const n = Number(value);
  if (value == null || Number.isNaN(n)) return "--";
  return `${fmtNum(n)} 元/吨`;
}

export function fmtPct(value: unknown): string {
  const n = Number(value);
  if (value == null || Number.isNaN(n)) return "--";
  return `${n >= 0 ? "+" : ""}${(n * 100).toFixed(2)}%`;
}

// ─── Class helpers ──────────────────────────────────────

export function tone(value: unknown): string {
  const n = Number(value);
  if (n > 0.005) return "text-red-600";
  if (n < -0.005) return "text-emerald-600";
  return "text-muted-foreground";
}

export function trendText(value: unknown): string {
  const n = Number(value);
  if (n > 0.02) return "上涨";
  if (n < -0.02) return "下跌";
  return "小幅波动";
}

// ─── Interval judgement ─────────────────────────────────

export function intervalJudgement(row: {
  interval_judgement?: string | null;
  predicted_return_p10?: number | null;
  predicted_return_p50?: number | null;
  predicted_return_p90?: number | null;
}): string {
  if (row.interval_judgement) return row.interval_judgement;
  const p10 = Number(row.predicted_return_p10);
  const p50 = Number(row.predicted_return_p50);
  const p90 = Number(row.predicted_return_p90);
  if (![p10, p50, p90].every(Number.isFinite)) return "--";
  if (p10 > 0 && p50 > 0 && p90 > 0) return "方向一致向上";
  if (p10 < 0 && p50 < 0 && p90 < 0) return "方向一致向下";
  if (p10 < 0 && p90 > 0) return "区间跨零";
  return "方向不明确";
}

export function reliabilityScoreText(row: {
  reliability_score?: number | null;
} | null): string {
  if (!row || row.reliability_score == null) return "--";
  return `${Math.round(Number(row.reliability_score))}/100`;
}

// ─── Date helpers ───────────────────────────────────────

export function todayText(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function addDays(date: string | null | undefined, days: number | null | undefined): string | null {
  if (!date || days == null) return null;
  const [year, month, day] = String(date).split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day + Number(days)));
  return parsed.toISOString().slice(0, 10);
}

export function toDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  return new Date(`${value}T00:00:00`);
}

// ─── Data extraction ────────────────────────────────────

export function historyDateOf(row: HistoryRow): string | null {
  return row.date || row.price_date || null;
}

export function historyPriceOf(row: HistoryRow): number | null {
  return row.actual_price ?? null;
}

export function forecastDateOf(detail: DetailResponse): string | null {
  return detail.forecast_date || detail.forecasts?.find((r) => r.forecast_date)?.forecast_date || null;
}

export function basePriceOf(detail: DetailResponse): number | null {
  return detail.base_price ?? detail.forecasts?.find((r) => r.base_price != null)?.base_price ?? null;
}

export function targetDateOf(row: ForecastRow): string {
  return row.forecast_target_date || addDays(row.forecast_date, row.horizon_day) || "--";
}

export function byHorizon(forecasts: ForecastRow[], horizon: number): ForecastRow | undefined {
  return forecasts.find((r) => Number(r.horizon_day) === horizon);
}

// ─── Chart series builder ───────────────────────────────

export function buildChartSeries(detail: DetailResponse): ChartPoint[] {
  const history: ChartPoint[] = (detail.history || [])
    .map((row) => ({
      date: historyDateOf(row) || "",
      actualPrice: Number(historyPriceOf(row)),
      pointType: "history" as const,
    }))
    .filter((row) => row.date && Number.isFinite(row.actualPrice));

  const forecastDate = forecastDateOf(detail);
  const bp = basePriceOf(detail);
  const start: ChartPoint[] =
    forecastDate && bp != null
      ? [
          {
            date: forecastDate,
            actualPrice: Number(bp),
            forecastPrice: Number(bp),
            forecastLow: Number(bp),
            forecastHigh: Number(bp),
            label: "预测基准",
            pointType: "forecast_start",
          },
        ]
      : [];

  const forecasts: ChartPoint[] = (detail.forecasts || [])
    .map((row) => ({
      date: targetDateOf(row),
      forecastPrice: Number(row.final_predicted_price ?? row.predicted_price_p50),
      forecastLow: row.predicted_price_p10 != null ? Number(row.predicted_price_p10) : undefined,
      forecastHigh: row.predicted_price_p90 != null ? Number(row.predicted_price_p90) : undefined,
      horizonDay: row.horizon_day,
      predictedReturn: row.final_predicted_return ?? row.predicted_return_p50,
      reliabilityScore: row.reliability_score,
      reliabilityNote: row.reliability_score_note,
      label: `${row.horizon_day} 天预测`,
      pointType: "forecast" as const,
    }))
    .filter((row) => row.date && Number.isFinite(row.forecastPrice));

  return [...history, ...start, ...forecasts].sort((a, b) => {
    const da = toDate(a.date);
    const db = toDate(b.date);
    return (da?.getTime() ?? 0) - (db?.getTime() ?? 0);
  });
}

// ─── API ────────────────────────────────────────────────

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "";

export async function fetchRanking(): Promise<MetalRanking[]> {
  const res = await fetch(`${API_BASE}/api/market/production-ranking`);
  if (!res.ok) throw new Error(`production-ranking ${res.status}`);
  return res.json();
}

export async function fetchDetail(params: {
  metal_code: string;
  forecast_date?: string;
  history_start_date?: string;
  history_end_date?: string;
}): Promise<DetailResponse> {
  const qs = new URLSearchParams({ metal_code: params.metal_code });
  if (params.forecast_date) qs.set("forecast_date", params.forecast_date);
  if (params.history_start_date) qs.set("history_start_date", params.history_start_date);
  if (params.history_end_date) qs.set("history_end_date", params.history_end_date);
  const res = await fetch(`${API_BASE}/api/market/production-detail?${qs.toString()}`);
  if (!res.ok) throw new Error(`production-detail ${res.status}`);
  return res.json();
}
