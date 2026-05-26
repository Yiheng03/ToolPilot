"use client";

import { Card, CardContent } from "@/components/ui/card";
import type { CurrentSignal, ForecastRow } from "@/lib/market-utils";
import {
  METAL_NAMES,
  fmtMoney,
  fmtPct,
  tone,
  byHorizon,
  reliabilityScoreText,
  intervalJudgement,
} from "@/lib/market-utils";

interface MetricGridProps {
  metalCode: string;
  metalName: string | null;
  basePrice: number | null;
  forecastDate: string | null;
  forecasts: ForecastRow[];
  currentSignal: CurrentSignal;
}

function ForecastCard({ title, price, predictedReturn }: { title: string; price: number | null; predictedReturn: number | null }) {
  const priceDisplay = price ?? null;
  const returnDisplay = predictedReturn ?? null;
  return (
    <Card>
      <CardContent className="p-4 relative overflow-hidden">
        <div className="absolute -top-6 -right-4 w-16 h-16 rounded-bl-full bg-primary/5" />
        <p className="text-xs font-bold text-muted-foreground relative z-10">{title}</p>
        <p className={`text-xl font-extrabold mt-1 relative z-10 ${tone(returnDisplay ?? 0)}`}>
          {fmtMoney(priceDisplay)}
        </p>
        <p className={`text-xs mt-1 relative z-10 ${tone(returnDisplay ?? 0)}`}>
          累计 {fmtPct(returnDisplay)}
        </p>
      </CardContent>
    </Card>
  );
}

export function MetricGrid({ metalCode, metalName, basePrice, forecastDate, forecasts, currentSignal }: MetricGridProps) {
  const f7 = byHorizon(forecasts, 7);
  const f30 = byHorizon(forecasts, 30);
  const f90 = byHorizon(forecasts, 90);
  const signal = currentSignal.reliability_score != null ? currentSignal : f30 || currentSignal;
  const name = metalName || METAL_NAMES[metalCode] || metalCode;

  return (
    <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
      <Card>
        <CardContent className="p-4 relative overflow-hidden">
          <div className="absolute -top-6 -right-4 w-16 h-16 rounded-bl-full bg-primary/5" />
          <p className="text-xs font-bold text-muted-foreground relative z-10">当前金属</p>
          <p className="text-xl font-extrabold mt-1 relative z-10">{metalCode || "--"}</p>
          <p className="text-xs mt-1 text-muted-foreground relative z-10">{name}</p>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4 relative overflow-hidden">
          <div className="absolute -top-6 -right-4 w-16 h-16 rounded-bl-full bg-primary/5" />
          <p className="text-xs font-bold text-muted-foreground relative z-10">最新历史价格</p>
          <p className="text-xl font-extrabold mt-1 relative z-10">{fmtMoney(basePrice)}</p>
          <p className="text-xs mt-1 text-muted-foreground relative z-10">{forecastDate || "--"}</p>
        </CardContent>
      </Card>

      <ForecastCard
        title="7天预测"
        price={f7?.final_predicted_price ?? f7?.predicted_price_p50 ?? null}
        predictedReturn={f7?.final_predicted_return ?? f7?.predicted_return_p50 ?? null}
      />

      <ForecastCard
        title="30天预测"
        price={f30?.final_predicted_price ?? f30?.predicted_price_p50 ?? null}
        predictedReturn={f30?.final_predicted_return ?? f30?.predicted_return_p50 ?? null}
      />

      <ForecastCard
        title="90天预测"
        price={f90?.final_predicted_price ?? f90?.predicted_price_p50 ?? null}
        predictedReturn={f90?.final_predicted_return ?? f90?.predicted_return_p50 ?? null}
      />

      <Card>
        <CardContent className="p-4 relative overflow-hidden">
          <div className="absolute -top-6 -right-4 w-16 h-16 rounded-bl-full bg-primary/5" />
          <p className="text-xs font-bold text-muted-foreground relative z-10">可靠性评分</p>
          <p className="text-xl font-extrabold mt-1 relative z-10">{reliabilityScoreText(signal)}</p>
          <p className="text-xs mt-1 text-muted-foreground relative z-10">
            {signal.reliability_score_note || intervalJudgement(f30 || {}) || "--"}
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
