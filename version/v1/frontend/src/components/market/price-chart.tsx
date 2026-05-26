"use client";

import { useMemo } from "react";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  ComposedChart,
  Line,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
  ResponsiveContainer,
} from "recharts";
import type { ChartPoint, DetailResponse } from "@/lib/market-utils";
import { buildChartSeries, forecastDateOf, fmtMoney, fmtNum, fmtPct, toDate } from "@/lib/market-utils";

interface PriceChartProps {
  detail: DetailResponse;
  historyStart?: string;
  historyEnd?: string;
}

interface ChartRow {
  ts: number;
  dateDisplay: string;
  fullDate: string;
  actualPrice?: number;
  forecastPrice?: number;
  bandTop?: number;
  bandBottom?: number;
  pointType: string;
  label?: string;
  predictedReturn?: number | null;
  reliabilityScore?: number | null;
  reliabilityNote?: string | null;
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: Array<{ payload: ChartRow }> }) {
  if (!active || !payload?.length) return null;
  const p = payload[0].payload;
  const isForecast = p.pointType !== "history";

  return (
    <div className="bg-card border border-border rounded-lg p-3 shadow-lg max-w-[260px]">
      <p className="text-xs font-bold mb-1">
        {p.fullDate} · {p.pointType === "history" ? "历史价格" : p.label || "预测价格"}
      </p>
      <p className="text-xs">
        价格：{fmtMoney(p.actualPrice ?? p.forecastPrice)}
      </p>
      {isForecast && p.predictedReturn != null && (
        <p className="text-xs">涨跌幅：{fmtPct(p.predictedReturn)}</p>
      )}
      {isForecast && p.bandBottom != null && p.bandTop != null && (
        <p className="text-xs">区间：{fmtNum(p.bandBottom)} - {fmtNum(p.bandTop)}</p>
      )}
      {isForecast && p.reliabilityScore != null && (
        <p className="text-xs">可靠性评分：{Math.round(Number(p.reliabilityScore))}/100</p>
      )}
      {isForecast && p.reliabilityNote && (
        <p className="text-xs">结论：{p.reliabilityNote}</p>
      )}
    </div>
  );
}

function formatXAxis(ts: number): string {
  const d = new Date(ts);
  return `${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function PriceChart({ detail, historyStart, historyEnd }: PriceChartProps) {
  const { chartData, forecastRefTs, xDomain, chartKey } = useMemo(() => {
    const startTs = historyStart ? toDate(historyStart)?.getTime() : undefined;
    const endTs = historyEnd ? toDate(historyEnd)?.getTime() : undefined;
    const series = buildChartSeries(detail);
    const fDate = forecastDateOf(detail);

    const chartData: ChartRow[] = series
      .map((p) => {
        const d = toDate(p.date);
        const ts = d ? d.getTime() : 0;
        const hasBand = p.forecastLow != null && p.forecastHigh != null;
        return {
          ts,
          dateDisplay: p.date.slice(5),
          fullDate: p.date,
          actualPrice: p.actualPrice ?? undefined,
          forecastPrice: p.forecastPrice ?? undefined,
          bandTop: hasBand ? p.forecastHigh! : undefined,
          bandBottom: hasBand ? p.forecastLow! : undefined,
          pointType: p.pointType,
          label: p.label,
          predictedReturn: p.predictedReturn,
          reliabilityScore: p.reliabilityScore,
          reliabilityNote: p.reliabilityNote,
        };
      })
      .filter((row) => {
        if (!Number.isFinite(row.ts) || row.ts <= 0) return false;
        if (startTs != null && row.ts < startTs) return false;
        if (endTs != null && row.pointType === "history" && row.ts > endTs) return false;
        return true;
      });
    const timestamps = chartData.map((row) => row.ts).filter((ts) => Number.isFinite(ts) && ts > 0);
    const minTs = timestamps.length ? Math.min(...timestamps) : 0;
    const maxTs = timestamps.length ? Math.max(...timestamps) : 1;
    const xDomain: [number, number] = minTs === maxTs ? [minTs - 86400000, maxTs + 86400000] : [minTs, maxTs];
    const chartKey =
      timestamps.length > 0
        ? `${detail.metal_code}-${historyStart || "all"}-${historyEnd || "all"}-${timestamps.length}-${xDomain[0]}-${xDomain[1]}`
        : `${detail.metal_code}-empty`;

    let forecastRefTs: number | undefined;
    if (fDate) {
      const fd = toDate(fDate);
      const ts = fd ? fd.getTime() : undefined;
      forecastRefTs = ts != null && (startTs == null || ts >= startTs) ? ts : undefined;
    }

    return { chartData, forecastRefTs, xDomain, chartKey };
  }, [detail, historyStart, historyEnd]);

  if (!chartData.length) {
    return (
      <Card>
        <CardContent className="p-6 text-center text-sm text-muted-foreground">
          暂无图表数据
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-2 pt-4 px-4">
        <div className="flex items-center justify-between">
          <div>
            <span className="text-xs font-extrabold text-primary uppercase">价格走势</span>
            <h2 className="text-base font-bold mt-0.5">历史与预测价格曲线</h2>
          </div>
          <div className="flex gap-4 text-xs text-muted-foreground">
            <span className="flex items-center gap-1.5">
              <span className="w-5 border-t-[3px] border-primary inline-block" />
              历史价格
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-5 border-t-[3px] border-dashed border-blue-400 inline-block" />
              预测价格
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-5 h-2 border border-blue-300 bg-blue-100 inline-block rounded-sm" />
              预测区间
            </span>
          </div>
        </div>
      </CardHeader>
      <CardContent className="px-2 pb-4">
        <ResponsiveContainer width="100%" height={400}>
          <ComposedChart key={chartKey} data={chartData} margin={{ top: 10, right: 20, left: 10, bottom: 5 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#eef0f6" />
            <XAxis
              dataKey="ts"
              type="number"
              domain={xDomain}
              allowDataOverflow
              tickFormatter={formatXAxis}
              tick={{ fontSize: 11, fill: "#8a8fa3" }}
              scale="time"
            />
            <YAxis
              tick={{ fontSize: 11, fill: "#868b9d" }}
              tickFormatter={(v: number) => fmtNum(v)}
              width={70}
              domain={["auto", "auto"]}
            />
            <Tooltip content={<CustomTooltip />} />

            {forecastRefTs != null && (
              <ReferenceLine
                x={forecastRefTs}
                stroke="#7e8192"
                strokeDasharray="4 4"
                label={{ value: "预测基准", position: "top", fontSize: 11, fill: "#5f6478" }}
              />
            )}

            <Area
              type="monotone"
              dataKey="bandTop"
              stroke="rgba(35, 131, 197, 0.3)"
              strokeWidth={1}
              fill="rgba(35, 131, 197, 0.08)"
              connectNulls
              name="区间上界"
              isAnimationActive={false}
            />
            <Area
              type="monotone"
              dataKey="bandBottom"
              stroke="rgba(35, 131, 197, 0.3)"
              strokeWidth={1}
              fill="rgba(35, 131, 197, 0.08)"
              connectNulls
              name="区间下界"
              isAnimationActive={false}
            />

            <Line
              type="monotone"
              dataKey="actualPrice"
              stroke="#443cc8"
              strokeWidth={2.5}
              dot={false}
              connectNulls
              name="历史价格"
              isAnimationActive={false}
            />
            <Line
              type="monotone"
              dataKey="forecastPrice"
              stroke="#2383c5"
              strokeWidth={2.5}
              strokeDasharray="7 6"
              dot={{ r: 3.5, fill: "#2383c5", stroke: "#fff", strokeWidth: 1.5 }}
              connectNulls
              name="预测价格"
              isAnimationActive={false}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
