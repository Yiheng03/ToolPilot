"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Header } from "@/components/header";
import { Footer } from "@/components/footer";
import { Badge } from "@/components/ui/badge";
import { MarketFilters } from "@/components/market/market-filters";
import { MetricGrid } from "@/components/market/metric-grid";
import { ModelDetails } from "@/components/market/model-details";
import { ForecastTable } from "@/components/market/forecast-table";
import { HistoryTable } from "@/components/market/history-table";
import {
  type MetalRanking,
  type DetailResponse,
  fetchRanking,
  fetchDetail,
  todayText,
  forecastDateOf,
  historyDateOf,
} from "@/lib/market-utils";

const PriceChart = dynamic(
  () => import("@/components/market/price-chart").then((m) => m.PriceChart),
  { ssr: false }
);

export default function MarketPage() {
  const [ranking, setRanking] = useState<MetalRanking[]>([]);
  const [detail, setDetail] = useState<DetailResponse | null>(null);
  const [selectedMetal, setSelectedMetal] = useState("");
  const [forecastDate, setForecastDate] = useState(todayText());
  const [historyStart, setHistoryStart] = useState("");
  const [historyEnd, setHistoryEnd] = useState("");
  const [forecastDateTouched, setForecastDateTouched] = useState(false);
  const [historyRangeTouched, setHistoryRangeTouched] = useState(false);
  const [status, setStatus] = useState("加载中...");
  const [isDemo, setIsDemo] = useState(false);

  const loadRanking = useCallback(async () => {
    try {
      const data = await fetchRanking();
      setRanking(data);
      if (!selectedMetal && data.length) {
        setSelectedMetal(data[0].metal_code);
      }
      setStatus(`基准日 ${detail ? forecastDateOf(detail) || "--" : "--"}`);
      setIsDemo(false);
    } catch (error) {
      setRanking([]);
      setSelectedMetal("");
      setDetail(null);
      setIsDemo(false);
      setStatus(error instanceof Error ? `market API failed: ${error.message}` : "market API failed");
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loadDetail = useCallback(async () => {
    if (!selectedMetal) return;
    try {
      const params: {
        metal_code: string;
        forecast_date?: string;
        history_start_date?: string;
        history_end_date?: string;
      } = { metal_code: selectedMetal };
      if (forecastDateTouched && forecastDate) params.forecast_date = forecastDate;
      if (historyRangeTouched && historyStart) params.history_start_date = historyStart;
      if (historyRangeTouched && historyEnd) params.history_end_date = historyEnd;
      const data = await fetchDetail(params);
      setDetail(data);
      applyDefaultDates(data);
      setStatus(`基准日 ${forecastDateOf(data) || "--"}`);
      setIsDemo(false);
    } catch (error) {
      setDetail(null);
      setIsDemo(false);
      setStatus(error instanceof Error ? `market API failed: ${error.message}` : "market API failed");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedMetal, forecastDate, historyStart, historyEnd, forecastDateTouched, historyRangeTouched]);

  function applyDefaultDates(data: DetailResponse) {
    if (!forecastDateTouched) {
      setForecastDate(todayText());
    }
    if (!historyRangeTouched) {
      const dates = (data.history || []).map(historyDateOf).filter(Boolean).sort() as string[];
      if (dates.length) {
        setHistoryStart(dates[0]);
        setHistoryEnd(dates[dates.length - 1]);
      }
    }
  }

  useEffect(() => {
    loadRanking();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (selectedMetal) {
      loadDetail();
    }
  }, [selectedMetal, forecastDate, historyStart, historyEnd, forecastDateTouched, historyRangeTouched, loadDetail]);

  const handleRefresh = () => {
    loadDetail();
  };

  const historyBounds = useMemo(() => {
    const dates = (detail?.history || []).map(historyDateOf).filter(Boolean).sort() as string[];
    return {
      min: dates[0] || "",
      max: dates[dates.length - 1] || "",
    };
  }, [detail]);

  const handleForecastDateChange = (v: string) => {
    setForecastDate(v);
    setForecastDateTouched(true);
  };

  const handleHistoryStartChange = (v: string) => {
    setHistoryStart(historyBounds.min && v && v < historyBounds.min ? historyBounds.min : v);
    setHistoryRangeTouched(true);
  };

  const handleHistoryEndChange = (v: string) => {
    setHistoryEnd(historyBounds.max && v && v > historyBounds.max ? historyBounds.max : v);
    setHistoryRangeTouched(true);
  };

  const filteredDetail = useMemo(() => {
    if (!detail) return null;
    let history = detail.history;
    if (historyStart) {
      history = history.filter((row) => {
        const date = historyDateOf(row);
        return date != null && date >= historyStart;
      });
    }
    if (historyEnd) {
      history = history.filter((row) => {
        const date = historyDateOf(row);
        return date != null && date <= historyEnd;
      });
    }
    return { ...detail, history };
  }, [detail, historyStart, historyEnd]);

  return (
    <div className="min-h-screen flex flex-col bg-background">
      <Header />
      <main className="flex-1">
      <section className="relative py-10 md:py-16 overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-accent/5 to-background" />
        <div className="absolute top-0 left-1/4 w-96 h-96 bg-primary/10 rounded-full blur-3xl" />
        <div className="absolute bottom-0 right-1/4 w-80 h-80 bg-accent/10 rounded-full blur-3xl" />

        <div className="container mx-auto px-4 relative z-10">
          <div className="max-w-3xl mx-auto text-center">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 text-primary text-sm font-medium mb-4">
              <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
              ToolPilot 工业智能分析
            </div>
            <h1 className="text-3xl md:text-5xl font-bold text-foreground mb-4">
              金属市场预测
            </h1>
            <p className="text-lg text-muted-foreground text-pretty">
              基于多模型融合的金属价格预测系统，提供区间概率、可靠性评分与采购建议
            </p>
          </div>
        </div>
      </section>

      <div className="container mx-auto px-4 pb-12 space-y-5">
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted-foreground">{status}</p>
          {isDemo && (
            <Badge variant="secondary" className="text-xs">演示模式</Badge>
          )}
        </div>

        <MarketFilters
          ranking={ranking}
          selectedMetal={selectedMetal}
          forecastDate={forecastDate}
          historyStart={historyStart}
          historyEnd={historyEnd}
          historyMin={historyBounds.min}
          historyMax={historyBounds.max}
          onMetalChange={setSelectedMetal}
          onForecastDateChange={handleForecastDateChange}
          onHistoryStartChange={handleHistoryStartChange}
          onHistoryEndChange={handleHistoryEndChange}
          onRefresh={handleRefresh}
        />

        {filteredDetail && (
          <>
            <MetricGrid
              metalCode={filteredDetail.metal_code}
              metalName={filteredDetail.metal_name}
              basePrice={filteredDetail.base_price}
              forecastDate={filteredDetail.forecast_date}
              forecasts={filteredDetail.forecasts}
              currentSignal={filteredDetail.current_signal}
            />

            <ModelDetails forecasts={filteredDetail.forecasts} />

            <PriceChart
              key={`${filteredDetail.metal_code}-${historyStart || "start"}-${historyEnd || "end"}`}
              detail={filteredDetail}
              historyStart={historyStart}
              historyEnd={historyEnd}
            />

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <ForecastTable forecasts={filteredDetail.forecasts} />
              <HistoryTable history={filteredDetail.history} />
            </div>
          </>
        )}
      </div>
      </main>
      <Footer />
    </div>
  );
}
