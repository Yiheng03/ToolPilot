"use client";

import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { HistoryRow } from "@/lib/market-utils";
import { historyDateOf, historyPriceOf, fmtNum, fmtPct, tone, toDate } from "@/lib/market-utils";

interface HistoryTableProps {
  history: HistoryRow[];
}

export function HistoryTable({ history }: HistoryTableProps) {
  const sorted = [...history]
    .sort((a, b) => {
      const da = toDate(historyDateOf(a));
      const db = toDate(historyDateOf(b));
      return (db?.getTime() ?? 0) - (da?.getTime() ?? 0);
    });

  return (
    <Card className="h-full">
      <CardHeader className="pb-2 pt-4 px-4">
        <span className="text-xs font-extrabold text-primary uppercase">历史数据</span>
        <h2 className="text-base font-bold mt-0.5">历史价格记录</h2>
      </CardHeader>
      <CardContent className="px-0 pb-4">
        {sorted.length === 0 ? (
          <p className="text-center text-sm text-muted-foreground py-8">暂无历史数据</p>
        ) : (
          <div className="max-h-[360px] overflow-y-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="text-xs">日期</TableHead>
                  <TableHead className="text-xs">价格</TableHead>
                  <TableHead className="text-xs">日涨跌</TableHead>
                  <TableHead className="text-xs">来源</TableHead>
                  <TableHead className="text-xs">类型</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sorted.map((row, index) => {
                  const price = historyPriceOf(row);
                  const previous = sorted[index + 1];
                  const previousPrice = previous ? historyPriceOf(previous) : null;
                  const change =
                    previousPrice && Number(previousPrice)
                      ? (Number(price) - Number(previousPrice)) / Number(previousPrice)
                      : null;
                  return (
                    <TableRow key={`${historyDateOf(row)}-${index}`}>
                      <TableCell className="text-xs">{historyDateOf(row) || "--"}</TableCell>
                      <TableCell className="text-xs">{fmtNum(price)}</TableCell>
                      <TableCell className={`text-xs font-medium ${tone(change)}`}>
                        {change == null ? "--" : fmtPct(change)}
                      </TableCell>
                      <TableCell className="text-xs">PostgreSQL</TableCell>
                      <TableCell className="text-xs">现货基准</TableCell>
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
