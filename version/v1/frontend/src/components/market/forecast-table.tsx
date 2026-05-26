"use client";

import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { ForecastRow } from "@/lib/market-utils";
import { fmtNum, fmtPct, targetDateOf, tone, trendText } from "@/lib/market-utils";

interface ForecastTableProps {
  forecasts: ForecastRow[];
}

export function ForecastTable({ forecasts }: ForecastTableProps) {
  return (
    <Card className="h-full">
      <CardHeader className="pb-2 pt-4 px-4">
        <span className="text-xs font-extrabold text-primary uppercase">预测数据</span>
        <h2 className="text-base font-bold mt-0.5">价格预测明细</h2>
      </CardHeader>
      <CardContent className="px-0 pb-4">
        {forecasts.length === 0 ? (
          <p className="text-center text-sm text-muted-foreground py-8">暂无预测数据</p>
        ) : (
          <div className="max-h-[360px] overflow-y-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="text-xs">预测日期</TableHead>
                  <TableHead className="text-xs">天数</TableHead>
                  <TableHead className="text-xs">预测价格</TableHead>
                  <TableHead className="text-xs">涨跌幅</TableHead>
                  <TableHead className="text-xs">下界P10</TableHead>
                  <TableHead className="text-xs">上界P90</TableHead>
                  <TableHead className="text-xs">趋势</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {forecasts.map((row) => {
                  const predictedReturn = row.final_predicted_return ?? row.predicted_return_p50;
                  return (
                    <TableRow key={row.horizon_day}>
                      <TableCell className="text-xs">{targetDateOf(row)}</TableCell>
                      <TableCell className="text-xs">{row.horizon_day ?? "--"}</TableCell>
                      <TableCell className="text-xs">{fmtNum(row.final_predicted_price ?? row.predicted_price_p50)}</TableCell>
                      <TableCell className={`text-xs font-medium ${tone(predictedReturn)}`}>
                        {fmtPct(predictedReturn)}
                      </TableCell>
                      <TableCell className="text-xs">{fmtNum(row.predicted_price_p10)}</TableCell>
                      <TableCell className="text-xs">{fmtNum(row.predicted_price_p90)}</TableCell>
                      <TableCell className="text-xs">{trendText(predictedReturn)}</TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
