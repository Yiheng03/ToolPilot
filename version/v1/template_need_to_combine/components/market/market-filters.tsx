"use client";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { MetalRanking } from "@/lib/market-utils";
import { METAL_NAMES } from "@/lib/market-utils";

interface MarketFiltersProps {
  ranking: MetalRanking[];
  selectedMetal: string;
  forecastDate: string;
  historyStart: string;
  historyEnd: string;
  historyMin?: string;
  historyMax?: string;
  onMetalChange: (code: string) => void;
  onForecastDateChange: (date: string) => void;
  onHistoryStartChange: (date: string) => void;
  onHistoryEndChange: (date: string) => void;
  onRefresh: () => void;
}

export function MarketFilters({
  ranking,
  selectedMetal,
  forecastDate,
  historyStart,
  historyEnd,
  historyMin,
  historyMax,
  onMetalChange,
  onForecastDateChange,
  onHistoryStartChange,
  onHistoryEndChange,
  onRefresh,
}: MarketFiltersProps) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
      <div className="space-y-1.5">
        <label className="text-xs font-semibold text-muted-foreground">金属品种</label>
        <Select value={selectedMetal} onValueChange={onMetalChange}>
          <SelectTrigger className="h-10">
            <SelectValue placeholder="选择金属" />
          </SelectTrigger>
          <SelectContent>
            {ranking.map((r) => (
              <SelectItem key={r.metal_code} value={r.metal_code}>
                {r.metal_code} {r.metal_name || METAL_NAMES[r.metal_code] || ""}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <label className="text-xs font-semibold text-muted-foreground">预测基准日</label>
        <Input
          type="date"
          className="h-10"
          value={forecastDate}
          onInput={(e) => onForecastDateChange(e.currentTarget.value)}
          onChange={(e) => onForecastDateChange(e.target.value)}
        />
      </div>

      <div className="space-y-1.5">
        <label className="text-xs font-semibold text-muted-foreground">历史起始日</label>
        <Input
          type="date"
          className="h-10"
          value={historyStart}
          min={historyMin}
          max={historyEnd || historyMax}
          onInput={(e) => onHistoryStartChange(e.currentTarget.value)}
          onChange={(e) => onHistoryStartChange(e.target.value)}
        />
      </div>

      <div className="space-y-1.5">
        <label className="text-xs font-semibold text-muted-foreground">历史结束日</label>
        <Input
          type="date"
          className="h-10"
          value={historyEnd}
          min={historyStart || historyMin}
          max={historyMax}
          onInput={(e) => onHistoryEndChange(e.currentTarget.value)}
          onChange={(e) => onHistoryEndChange(e.target.value)}
        />
      </div>

      <div className="flex items-end">
        <Button onClick={onRefresh} className="h-10 w-full bg-gradient-to-r from-primary to-accent hover:opacity-90 text-white font-bold">
          刷新
        </Button>
      </div>
    </div>
  );
}
