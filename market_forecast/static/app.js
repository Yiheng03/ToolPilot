const state = {
  metals: [],
  batches: [],
  selectedMetal: "CU",
  selectedBatch: "",
  history: [],
  forecasts: [],
  summary: [],
  modelRun: null,
};

const els = {
  metalSelect: document.querySelector("#metalSelect"),
  batchSelect: document.querySelector("#batchSelect"),
  historyStart: document.querySelector("#historyStart"),
  historyEnd: document.querySelector("#historyEnd"),
  forecastStart: document.querySelector("#forecastStart"),
  forecastEnd: document.querySelector("#forecastEnd"),
  refreshButton: document.querySelector("#refreshButton"),
  batchBadge: document.querySelector("#batchBadge"),
  metricGrid: document.querySelector("#metricGrid"),
  chart: document.querySelector("#priceChart"),
  chartWrap: document.querySelector("#chartWrap"),
  chartTooltip: document.querySelector("#chartTooltip"),
  chartEmpty: document.querySelector("#chartEmpty"),
  forecastTable: document.querySelector("#forecastTable"),
  historyTable: document.querySelector("#historyTable"),
  forecastEmpty: document.querySelector("#forecastEmpty"),
  historyEmpty: document.querySelector("#historyEmpty"),
  modelInfo: document.querySelector("#modelInfo"),
};

function isoDate(date) {
  const d = new Date(date);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 10);
}

function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

function formatPrice(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "--";
  return Number(value).toLocaleString("zh-CN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatPct(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "--";
  const n = Number(value);
  return `${n >= 0 ? "+" : ""}${n.toFixed(2)}%`;
}

function pctClass(value) {
  const n = Number(value);
  if (Number.isNaN(n) || n === 0) return "flat";
  return n > 0 ? "up" : "down";
}

function forecastPointLabel(row) {
  if (row?.tooltip_label) return row.tooltip_label;
  return row?.curve_type === "direct_horizon_forecast_point"
    ? "模型直接预测点"
    : "插值生成曲线点";
}

async function api(path, params = {}) {
  const url = new URL(path, window.location.origin);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== null && value !== undefined && value !== "") url.searchParams.set(key, value);
  });
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.detail || payload.error || "API request failed");
  }
  return payload;
}

function setDefaultDates() {
  const today = new Date();
  els.historyEnd.value = isoDate(today);
  els.historyStart.value = isoDate(addDays(today, -180));
  els.forecastStart.value = isoDate(addDays(today, 1));
  els.forecastEnd.value = isoDate(addDays(today, 90));
}

function renderSelects() {
  els.metalSelect.innerHTML = state.metals
    .map((item) => `<option value="${item.metal_code}">${item.metal_code}｜${item.metal_name || item.metal_code}</option>`)
    .join("");
  if (state.metals.some((item) => item.metal_code === state.selectedMetal)) {
    els.metalSelect.value = state.selectedMetal;
  } else if (state.metals[0]) {
    state.selectedMetal = state.metals[0].metal_code;
    els.metalSelect.value = state.selectedMetal;
  }

  els.batchSelect.innerHTML = state.batches
    .map((item) => {
      const label = `${item.forecast_batch_id}｜${item.metal_count || 0} 金属`;
      return `<option value="${item.forecast_batch_id}">${label}</option>`;
    })
    .join("");
  if (state.selectedBatch) els.batchSelect.value = state.selectedBatch;
}

function metricCard(label, value, sub = "", className = "") {
  return `
    <article class="metric-card">
      <div class="metric-label">${label}</div>
      <div class="metric-value ${className}">${value}</div>
      <div class="metric-sub">${sub}</div>
    </article>
  `;
}

function summaryFor(day) {
  return state.summary.find((item) => Number(item.horizon_day) === day);
}

function renderMetrics() {
  const latest = state.history[state.history.length - 1];
  const s7 = summaryFor(7);
  const s30 = summaryFor(30);
  const s90 = summaryFor(90);
  const model = state.modelRun || {};
  const metalName = latest?.metal_name || state.forecasts[0]?.metal_name || model.metal_name || state.selectedMetal;

  const cards = [
    metricCard("当前金属", `${state.selectedMetal}`, metalName),
    metricCard("最新历史价格", `${formatPrice(latest?.price)} 元/吨`, latest?.price_date || "--"),
    metricCard("7 天预测", `${formatPrice(s7?.predicted_price)} 元/吨`, `累计 ${formatPct(s7?.cumulative_change_pct)}`, pctClass(s7?.cumulative_change_pct)),
    metricCard("30 天预测", `${formatPrice(s30?.predicted_price)} 元/吨`, `累计 ${formatPct(s30?.cumulative_change_pct)}`, pctClass(s30?.cumulative_change_pct)),
    metricCard("90 天预测", `${formatPrice(s90?.predicted_price)} 元/吨`, `累计 ${formatPct(s90?.cumulative_change_pct)}`, pctClass(s90?.cumulative_change_pct)),
    metricCard("模型指标", `${formatPct(model.mape_price)} MAPE`, `方向准确率 ${formatPct(model.direction_accuracy)}`),
  ];

  els.metricGrid.innerHTML = cards.join("");
}

function renderTables() {
  els.forecastEmpty.classList.toggle("hidden", state.forecasts.length > 0);
  els.historyEmpty.classList.toggle("hidden", state.history.length > 0);

  els.forecastTable.innerHTML = state.forecasts.map((row) => `
    <tr>
      <td>${row.forecast_date || "--"}</td>
      <td>${row.horizon_day ?? "--"}</td>
      <td>${formatPrice(row.predicted_price)}</td>
      <td class="${pctClass(row.predicted_return_pct)}">${formatPct(row.predicted_return_pct)}</td>
      <td>${formatPrice(row.lower_bound_price)}</td>
      <td>${formatPrice(row.upper_bound_price)}</td>
      <td>${forecastPointLabel(row)}</td>
    </tr>
  `).join("");

  const recentHistory = state.history.slice(-80).reverse();
  els.historyTable.innerHTML = recentHistory.map((row) => `
    <tr>
      <td>${row.price_date || "--"}</td>
      <td>${formatPrice(row.price)}</td>
      <td class="${pctClass(row.change_pct)}">${formatPct(row.change_pct)}</td>
      <td>${row.source_provider || "--"}</td>
      <td>${row.price_type || "--"}</td>
    </tr>
  `).join("");
}

function renderModelInfo() {
  const model = state.modelRun;
  if (!model) {
    els.modelInfo.innerHTML = `<div class="empty-state">暂无模型运行信息。</div>`;
    return;
  }
  const items = [
    ["预测批次", model.forecast_batch_id],
    ["模型", `${model.model_name || "--"} ${model.model_version || ""}`.trim()],
    ["训练 / 测试行数", `${model.train_rows ?? "--"} / ${model.test_rows ?? "--"}`],
    ["MAE / RMSE", `${formatPrice(model.mae_price)} / ${formatPrice(model.rmse_price)}`],
    ["MAPE", formatPct(model.mape_price)],
    ["方向准确率", formatPct(model.direction_accuracy)],
    ["状态", model.run_status || "--"],
    ["完成时间", model.finished_at ? model.finished_at.replace("T", " ").slice(0, 19) : "--"],
  ];
  els.modelInfo.innerHTML = items.map(([label, value]) => `
    <div class="model-item"><span>${label}</span><strong>${value || "--"}</strong></div>
  `).join("");
}

function getChartData() {
  const history = state.history.map((row) => ({
    date: row.price_date,
    value: Number(row.price),
    change: row.change_pct,
    type: "history",
    label: "历史价格",
  }));
  const forecasts = state.forecasts.map((row) => ({
    date: row.forecast_date,
    value: Number(row.predicted_price),
    lower: row.lower_bound_price === null ? null : Number(row.lower_bound_price),
    upper: row.upper_bound_price === null ? null : Number(row.upper_bound_price),
    change: row.predicted_return_pct,
    type: "forecast",
    curveType: row.curve_type,
    pointLabel: forecastPointLabel(row),
    label: forecastPointLabel(row),
  }));
  return [...history, ...forecasts].filter((item) => item.date && Number.isFinite(item.value));
}

function linePath(points) {
  return points.map((point, index) => `${index === 0 ? "M" : "L"} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`).join(" ");
}

function renderChart() {
  const data = getChartData();
  const hasHistory = state.history.length > 0;
  const hasForecast = state.forecasts.length > 0;

  if (!hasHistory || !hasForecast) {
    const messages = [];
    if (!hasHistory) messages.push("该时间范围暂无历史价格数据。");
    if (!hasForecast) messages.push("暂无预测数据，请先运行预测脚本。");
    els.chartEmpty.textContent = messages.join(" ");
    els.chartEmpty.classList.remove("hidden");
  } else {
    els.chartEmpty.classList.add("hidden");
  }

  const width = els.chartWrap.clientWidth || 900;
  const height = els.chartWrap.clientHeight || 430;
  const margin = { top: 28, right: 34, bottom: 42, left: 72 };
  els.chart.setAttribute("viewBox", `0 0 ${width} ${height}`);

  if (data.length < 2) {
    els.chart.innerHTML = "";
    return;
  }

  const dates = data.map((item) => new Date(`${item.date}T00:00:00`).getTime());
  const minTime = Math.min(...dates);
  const maxTime = Math.max(...dates);
  const values = data.flatMap((item) => [item.value, item.lower, item.upper]).filter(Number.isFinite);
  const minValue = Math.min(...values);
  const maxValue = Math.max(...values);
  const paddingValue = Math.max((maxValue - minValue) * 0.12, 1);
  const yMin = minValue - paddingValue;
  const yMax = maxValue + paddingValue;
  const innerW = width - margin.left - margin.right;
  const innerH = height - margin.top - margin.bottom;
  const x = (dateText) => {
    const time = new Date(`${dateText}T00:00:00`).getTime();
    return margin.left + ((time - minTime) / Math.max(maxTime - minTime, 1)) * innerW;
  };
  const y = (value) => margin.top + (1 - (value - yMin) / Math.max(yMax - yMin, 1)) * innerH;

  const historyPoints = state.history
    .filter((row) => Number.isFinite(Number(row.price)))
    .map((row) => ({ x: x(row.price_date), y: y(Number(row.price)), raw: row }));
  const forecastPoints = state.forecasts
    .filter((row) => Number.isFinite(Number(row.predicted_price)))
    .map((row) => ({ x: x(row.forecast_date), y: y(Number(row.predicted_price)), raw: row }));
  const upperPoints = state.forecasts
    .filter((row) => Number.isFinite(Number(row.upper_bound_price)))
    .map((row) => ({ x: x(row.forecast_date), y: y(Number(row.upper_bound_price)) }));
  const lowerPoints = state.forecasts
    .filter((row) => Number.isFinite(Number(row.lower_bound_price)))
    .map((row) => ({ x: x(row.forecast_date), y: y(Number(row.lower_bound_price)) }))
    .reverse();
  const rangePath = upperPoints.length && lowerPoints.length
    ? `${linePath(upperPoints)} ${lowerPoints.map((point) => `L ${point.x.toFixed(2)} ${point.y.toFixed(2)}`).join(" ")} Z`
    : "";

  const grid = Array.from({ length: 5 }, (_, index) => {
    const yy = margin.top + (innerH / 4) * index;
    const value = yMax - ((yMax - yMin) / 4) * index;
    return `<line x1="${margin.left}" y1="${yy}" x2="${width - margin.right}" y2="${yy}" stroke="#edf0f8"/><text x="18" y="${yy + 4}" fill="#7a809c" font-size="11">${formatPrice(value)}</text>`;
  }).join("");

  const tickCount = Math.min(6, data.length);
  const ticks = Array.from({ length: tickCount }, (_, index) => {
    const time = minTime + ((maxTime - minTime) / Math.max(tickCount - 1, 1)) * index;
    const label = isoDate(time);
    const xx = margin.left + (innerW / Math.max(tickCount - 1, 1)) * index;
    return `<text x="${xx}" y="${height - 16}" text-anchor="middle" fill="#7a809c" font-size="11">${label.slice(5)}</text>`;
  }).join("");

  const baseDate = state.forecasts[0]?.base_price_date;
  const baseLine = baseDate
    ? `<line x1="${x(baseDate)}" y1="${margin.top}" x2="${x(baseDate)}" y2="${height - margin.bottom}" stroke="#1e2a6f" stroke-dasharray="4 5"/><text x="${x(baseDate) + 6}" y="${margin.top + 14}" fill="#1e2a6f" font-size="12">基准日 ${baseDate}</text>`
    : "";

  els.chart.innerHTML = `
    <rect x="0" y="0" width="${width}" height="${height}" fill="transparent"/>
    ${grid}
    ${ticks}
    ${rangePath ? `<path d="${rangePath}" fill="rgba(23,67,242,0.12)" stroke="none"/>` : ""}
    ${baseLine}
    ${historyPoints.length ? `<path d="${linePath(historyPoints)}" fill="none" stroke="#4838db" stroke-width="3" stroke-linecap="round"/>` : ""}
    ${forecastPoints.length ? `<path d="${linePath(forecastPoints)}" fill="none" stroke="#0b86d1" stroke-width="3" stroke-dasharray="8 7" stroke-linecap="round"/>` : ""}
    ${historyPoints.map((point) => `<circle cx="${point.x}" cy="${point.y}" r="2.5" fill="#4838db"/>`).join("")}
    ${forecastPoints.map((point) => {
      const direct = point.raw.curve_type === "direct_horizon_forecast_point";
      return `<circle cx="${point.x}" cy="${point.y}" r="${direct ? 5 : 2.4}" fill="${direct ? "#1743f2" : "#0b86d1"}" stroke="#fff" stroke-width="${direct ? 2 : 0}"/>`;
    }).join("")}
  `;

  const interactive = [
    ...historyPoints.map((point) => ({
      x: point.x,
      y: point.y,
      date: point.raw.price_date,
      label: "历史价格",
      price: point.raw.price,
      change: point.raw.change_pct,
    })),
    ...forecastPoints.map((point) => ({
      x: point.x,
      y: point.y,
      date: point.raw.forecast_date,
      label: forecastPointLabel(point.raw),
      price: point.raw.predicted_price,
      change: point.raw.predicted_return_pct,
      horizon: point.raw.horizon_day,
      method: point.raw.forecast_method,
    })),
  ];

  els.chartWrap.onmousemove = (event) => {
    if (!interactive.length) return;
    const rect = els.chartWrap.getBoundingClientRect();
    const mx = event.clientX - rect.left;
    const nearest = interactive.reduce((best, item) => (
      Math.abs(item.x - mx) < Math.abs(best.x - mx) ? item : best
    ), interactive[0]);
    els.chartTooltip.innerHTML = `
      <strong>${nearest.date}</strong>
      <div>${nearest.label}${nearest.horizon ? ` · ${nearest.horizon}d` : ""}</div>
      <div>${formatPrice(nearest.price)} 元/吨</div>
      <div>涨跌幅：<span class="${pctClass(nearest.change)}">${formatPct(nearest.change)}</span></div>
      ${nearest.method ? `<div>${nearest.method}</div>` : ""}
    `;
    els.chartTooltip.style.left = `${Math.min(Math.max(nearest.x + 12, 8), rect.width - 196)}px`;
    els.chartTooltip.style.top = `${Math.max(nearest.y - 48, 8)}px`;
    els.chartTooltip.classList.remove("hidden");
  };
  els.chartWrap.onmouseleave = () => els.chartTooltip.classList.add("hidden");
}

function renderAll() {
  els.batchBadge.textContent = state.selectedBatch ? `预测批次：${state.selectedBatch}` : "暂无成功预测批次";
  renderMetrics();
  renderTables();
  renderModelInfo();
  renderChart();
}

async function loadHistory() {
  state.history = await api("/api/market/history", {
    metal_code: state.selectedMetal,
    start_date: els.historyStart.value,
    end_date: els.historyEnd.value,
  });
  renderAll();
}

async function loadForecasts() {
  state.forecasts = await api("/api/market/forecasts", {
    metal_code: state.selectedMetal,
    forecast_batch_id: state.selectedBatch,
    start_date: els.forecastStart.value,
    end_date: els.forecastEnd.value,
  });
  renderAll();
}

async function loadForecastBundle() {
  const [forecasts, summary, modelRun] = await Promise.all([
    api("/api/market/forecasts", {
      metal_code: state.selectedMetal,
      forecast_batch_id: state.selectedBatch,
      start_date: els.forecastStart.value,
      end_date: els.forecastEnd.value,
    }),
    api("/api/market/forecast-summary", {
      metal_code: state.selectedMetal,
      forecast_batch_id: state.selectedBatch,
    }),
    api("/api/market/model-run", {
      metal_code: state.selectedMetal,
      forecast_batch_id: state.selectedBatch,
    }),
  ]);
  state.forecasts = forecasts || [];
  state.summary = summary || [];
  state.modelRun = modelRun || null;
  renderAll();
}

async function loadAll() {
  try {
    els.refreshButton.disabled = true;
    const [history] = await Promise.all([
      api("/api/market/history", {
        metal_code: state.selectedMetal,
        start_date: els.historyStart.value,
        end_date: els.historyEnd.value,
      }),
      loadForecastBundle(),
    ]);
    state.history = history || [];
    renderAll();
  } catch (error) {
    els.chartEmpty.textContent = `加载失败：${error.message}`;
    els.chartEmpty.classList.remove("hidden");
  } finally {
    els.refreshButton.disabled = false;
  }
}

async function init() {
  setDefaultDates();
  try {
    const [metals, batches, latest] = await Promise.all([
      api("/api/market/metals"),
      api("/api/market/forecast-batches"),
      api("/api/market/forecast-batches/latest"),
    ]);
    state.metals = metals || [];
    state.batches = batches || [];
    state.selectedBatch = latest?.forecast_batch_id || state.batches[0]?.forecast_batch_id || "";
    renderSelects();
    await loadAll();
  } catch (error) {
    els.chartEmpty.textContent = `初始化失败：${error.message}`;
    els.chartEmpty.classList.remove("hidden");
  }
}

els.metalSelect.addEventListener("change", async () => {
  state.selectedMetal = els.metalSelect.value;
  await loadAll();
});

els.batchSelect.addEventListener("change", async () => {
  state.selectedBatch = els.batchSelect.value;
  await loadForecastBundle();
});

els.historyStart.addEventListener("change", loadHistory);
els.historyEnd.addEventListener("change", loadHistory);
els.forecastStart.addEventListener("change", loadForecasts);
els.forecastEnd.addEventListener("change", loadForecasts);
els.refreshButton.addEventListener("click", loadAll);
window.addEventListener("resize", renderChart);

init();
