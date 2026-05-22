"use client";

import { Card, CardContent } from "@/components/ui/card";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";
import { ChevronDown } from "lucide-react";
import type { ForecastRow } from "@/lib/market-utils";
import { fmtNum, fmtPct, reliabilityScoreText, intervalJudgement } from "@/lib/market-utils";

interface ModelDetailsProps {
  forecasts: ForecastRow[];
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-center py-1 border-b border-border/30 last:border-b-0">
      <span className="text-xs text-muted-foreground">{label}</span>
      <b className="text-xs">{value}</b>
    </div>
  );
}

function DetailCard({ row }: { row: ForecastRow }) {
  const drivers = row.key_drivers || {};
  const scoreParts = row.reliability_score_breakdown || {};

  return (
    <Card>
      <CardContent className="p-4">
        <h3 className="text-sm font-bold mb-2">{row.horizon_day ?? "--"} 天预测</h3>
        <DetailRow label="可靠性评分" value={reliabilityScoreText(row)} />
        <DetailRow label="评分结论" value={row.reliability_score_note || "--"} />
        <DetailRow label="区间判断" value={intervalJudgement(row)} />
        <DetailRow label="数据贡献" value={scoreParts.data_quality == null ? "--" : `${scoreParts.data_quality}/35`} />
        <DetailRow label="方向贡献" value={scoreParts.direction_interval == null ? "--" : `${scoreParts.direction_interval}/30`} />
        <DetailRow label="宽度贡献" value={scoreParts.interval_width == null ? "--" : `${scoreParts.interval_width}/25`} />
        <DetailRow label="信号贡献" value={scoreParts.median_signal == null ? "--" : `${scoreParts.median_signal}/10`} />
        <DetailRow label="数据质量" value={fmtNum(row.data_quality_score)} />
        <DetailRow label="区间宽度" value={row.interval_width == null ? "--" : fmtPct(row.interval_width)} />
        <DetailRow label="波动水平" value={row.volatility_level || "--"} />
        <DetailRow label="风险等级" value={row.risk_level || "--"} />
        <DetailRow label="相对强度排名" value={row.relative_strength_rank ?? "--"} />
        <DetailRow label="基础模型" value={fmtPct(drivers.base_lgb)} />
        <DetailRow label="市场因子" value={fmtPct(drivers.market_factor)} />
        <DetailRow label="超额收益模型" value={fmtPct(drivers.catboost_excess)} />
        <DetailRow label="配对调整" value={fmtPct(drivers.pair_adjustment)} />
      </CardContent>
    </Card>
  );
}

export function ModelDetails({ forecasts }: ModelDetailsProps) {
  if (!forecasts.length) {
    return (
      <Card>
        <CardContent className="p-6 text-center text-sm text-muted-foreground">
          暂无模型指标数据
        </CardContent>
      </Card>
    );
  }

  return (
    <Collapsible defaultOpen={false}>
      <Card>
        <CollapsibleTrigger className="flex items-center justify-between w-full p-4 hover:bg-muted/50 transition-colors rounded-t-lg">
          <div className="flex items-center gap-2">
            <span className="text-xs font-extrabold text-primary uppercase">模型详情</span>
            <h2 className="text-base font-bold">模型指标分解</h2>
          </div>
          <ChevronDown className="h-4 w-4 text-muted-foreground transition-transform duration-200 [[data-state=open]>&]:rotate-180" />
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="px-4 pb-4 grid grid-cols-1 md:grid-cols-3 gap-3">
            {forecasts.map((row) => (
              <DetailCard key={row.horizon_day} row={row} />
            ))}
          </div>
        </CollapsibleContent>
      </Card>
    </Collapsible>
  );
}
