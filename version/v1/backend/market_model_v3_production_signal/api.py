from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
import math
import sys
from pathlib import Path
from typing import Any

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import MODEL_VERSION, query_dataframe
else:
    from .common import MODEL_VERSION, query_dataframe


FORECAST_COLUMNS = [
    "forecast_date",
    "horizon_day",
    "metal_code",
    "metal_name",
    "base_price",
    "final_predicted_return",
    "final_predicted_price",
    "predicted_return_p10",
    "predicted_return_p50",
    "predicted_return_p90",
    "predicted_price_p10",
    "predicted_price_p50",
    "predicted_price_p90",
    "relative_strength_rank",
    "volatility_level",
    "risk_level",
    "procurement_signal",
    "procurement_advice",
    "key_drivers",
    "data_quality_score",
    "model_reliability_level",
]


def api_value(value: Any) -> Any:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    return value


def rows_to_dicts(df):
    if df.empty:
        return []
    return [{key: api_value(value) for key, value in row.items()} for row in df.to_dict(orient="records")]


def latest_forecast_date_clause(model_version: str | None = None) -> tuple[str, list]:
    return (
        "forecast_date = (SELECT max(forecast_date) FROM market_production_forecasts WHERE model_version = %s)",
        [model_version or MODEL_VERSION],
    )


def latest_forecast_date(model_version: str | None = None) -> str | None:
    rows = query_dataframe(
        "SELECT max(forecast_date) AS forecast_date FROM market_production_forecasts WHERE model_version = %s",
        (model_version or MODEL_VERSION,),
    )
    if rows.empty:
        return None
    return api_value(rows.iloc[0]["forecast_date"])


def table_exists(table_name: str) -> bool:
    rows = query_dataframe("SELECT to_regclass(%s) AS regclass", (table_name,))
    return bool(not rows.empty and rows.iloc[0]["regclass"] is not None)


def history_source_sql() -> str | None:
    if table_exists("market_price_history"):
        return """
            SELECT price_date AS date, avg(price)::numeric(18,6) AS actual_price
            FROM market_price_history
            WHERE metal_code = %s
              AND price_date IS NOT NULL
              AND price IS NOT NULL
              {date_filter}
            GROUP BY price_date
            ORDER BY price_date
        """
    if table_exists("normalized_market_prices"):
        return """
            SELECT price_date AS date, avg(price)::numeric(18,6) AS actual_price
            FROM normalized_market_prices
            WHERE metal_code = %s
              AND price_date IS NOT NULL
              AND price IS NOT NULL
              AND is_available IS DISTINCT FROM false
              {date_filter}
            GROUP BY price_date
            ORDER BY price_date
        """
    if table_exists("market_price_series"):
        return """
            SELECT price_date AS date, avg(price)::numeric(18,6) AS actual_price
            FROM market_price_series
            WHERE commodity_code = %s
              AND price_date IS NOT NULL
              AND price IS NOT NULL
              {date_filter}
            GROUP BY price_date
            ORDER BY price_date
        """
    return None


def load_history(
    metal_code: str,
    history_start_date: str | None = None,
    history_end_date: str | None = None,
    model_version: str | None = None,
):
    date_clauses: list[str] = []
    params: list = [metal_code]
    if history_start_date:
        date_clauses.append("AND price_date >= %s")
        params.append(history_start_date)
    if history_end_date:
        date_clauses.append("AND price_date <= %s")
        params.append(history_end_date)
    date_filter = "\n".join(date_clauses)
    source_sql = history_source_sql()
    if source_sql:
        return query_dataframe(source_sql.format(date_filter=date_filter), tuple(params))

    fallback_clauses = ["model_version = %s", "metal_code = %s"]
    fallback_params: list = [model_version or MODEL_VERSION, metal_code]
    if history_start_date:
        fallback_clauses.append("forecast_date >= %s")
        fallback_params.append(history_start_date)
    if history_end_date:
        fallback_clauses.append("forecast_date <= %s")
        fallback_params.append(history_end_date)
    return query_dataframe(
        f"""
        SELECT forecast_date AS date, avg(base_price)::numeric(18,6) AS actual_price
        FROM market_production_forecasts
        WHERE {" AND ".join(fallback_clauses)}
        GROUP BY forecast_date
        ORDER BY forecast_date
        LIMIT 365
        """,
        tuple(fallback_params),
    )


def clean_number(value: Any) -> float | None:
    try:
        if value is None:
            return None
        number = float(value)
        if math.isnan(number) or math.isinf(number):
            return None
        return number
    except (TypeError, ValueError):
        return None


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def interval_judgement(p10: float | None, p50: float | None, p90: float | None) -> str:
    if p10 is None or p50 is None or p90 is None:
        return "区间数据缺失"
    if p10 > 0 and p50 > 0 and p90 > 0:
        return "方向一致向上"
    if p10 < 0 and p50 < 0 and p90 < 0:
        return "方向一致向下"
    if p10 < 0 < p90:
        return "区间跨零"
    return "方向不明确"


def reliability_score(row: dict[str, Any]) -> dict[str, Any]:
    p10 = clean_number(row.get("predicted_return_p10"))
    p50 = clean_number(row.get("predicted_return_p50"))
    p90 = clean_number(row.get("predicted_return_p90"))
    quality = clean_number(row.get("data_quality_score")) or 0.0
    quality = clamp(quality, 0.0, 1.0)

    data_score = round(quality * 35)
    judgement = interval_judgement(p10, p50, p90)
    if p10 is None or p50 is None or p90 is None:
        direction_score = 0
        width_score = 0
        signal_score = 0
        interval_width = None
    else:
        interval_width = max(0.0, p90 - p10)
        if judgement in {"方向一致向上", "方向一致向下"}:
            direction_score = 30
        elif judgement == "区间跨零":
            direction_score = 10
        else:
            direction_score = 16

        if interval_width <= 0.03:
            width_score = 25
        elif interval_width <= 0.06:
            width_score = 19
        elif interval_width <= 0.10:
            width_score = 13
        elif interval_width <= 0.18:
            width_score = 7
        else:
            width_score = 2

        center = abs(p50)
        if center >= 0.03:
            signal_score = 10
        elif center >= 0.015:
            signal_score = 7
        elif center >= 0.005:
            signal_score = 4
        else:
            signal_score = 1

    score = int(clamp(data_score + direction_score + width_score + signal_score, 0, 100))
    if score >= 85:
        note = "高稳定"
    elif score >= 70:
        note = "较稳定"
    elif score >= 55:
        note = "可参考"
    elif score >= 40:
        note = "需谨慎"
    else:
        note = "弱参考"

    reasons = [
        f"数据质量贡献 {data_score}/35",
        f"方向区间贡献 {direction_score}/30：{judgement}",
        f"区间宽度贡献 {width_score}/25",
        f"中位信号贡献 {signal_score}/10",
    ]
    return {
        "reliability_score": score,
        "reliability_score_note": note,
        "interval_judgement": judgement,
        "interval_width": interval_width,
        "reliability_score_breakdown": {
            "data_quality": data_score,
            "direction_interval": direction_score,
            "interval_width": width_score,
            "median_signal": signal_score,
        },
        "reliability_score_reasons": reasons,
    }


def enrich_forecast_row(row: dict[str, Any]) -> dict[str, Any]:
    enriched = {key: api_value(value) for key, value in row.items()}
    forecast_date_value = row.get("forecast_date")
    horizon_day = row.get("horizon_day")
    if forecast_date_value is not None and horizon_day is not None:
        if isinstance(forecast_date_value, str):
            start_date = datetime.fromisoformat(forecast_date_value).date()
        else:
            start_date = forecast_date_value
        enriched["forecast_target_date"] = (start_date + timedelta(days=int(horizon_day))).isoformat()
    base_price = row.get("base_price")
    for suffix in ["p10", "p50", "p90"]:
        price_key = f"predicted_price_{suffix}"
        return_key = f"predicted_return_{suffix}"
        if enriched.get(price_key) is None and base_price is not None and row.get(return_key) is not None:
            enriched[price_key] = api_value(Decimal(str(base_price)) * Decimal(str(1 + float(row[return_key]))))
    enriched.update(reliability_score(row))
    return enriched


def get_production_forecasts(
    model_version: str | None = None,
    horizon_day: int | None = None,
    metal_code: str | None = None,
    forecast_date: str | None = None,
):
    clauses = ["model_version = %s"]
    params: list = [model_version or MODEL_VERSION]
    if horizon_day is not None:
        clauses.append("horizon_day = %s")
        params.append(horizon_day)
    if metal_code:
        clauses.append("metal_code = %s")
        params.append(metal_code)
    if forecast_date:
        clauses.append("forecast_date = %s")
        params.append(forecast_date)
    else:
        clause, clause_params = latest_forecast_date_clause(model_version)
        clauses.append(clause)
        params.extend(clause_params)
    sql = f"""
        SELECT {", ".join(FORECAST_COLUMNS)}
        FROM market_production_forecasts
        WHERE {" AND ".join(clauses)}
        ORDER BY horizon_day, relative_strength_rank NULLS LAST, metal_code
    """
    rows = query_dataframe(sql, tuple(params))
    return [enrich_forecast_row(row) for row in rows.to_dict(orient="records")] if not rows.empty else []


def get_production_ranking(model_version: str | None = None, forecast_date: str | None = None):
    clauses = ["model_version = %s", "horizon_day = 30"]
    params: list = [model_version or MODEL_VERSION]
    if forecast_date:
        clauses.append("forecast_date = %s")
        params.append(forecast_date)
    else:
        clause, clause_params = latest_forecast_date_clause(model_version)
        clauses.append(clause)
        params.extend(clause_params)
    sql = f"""
        SELECT forecast_date, horizon_day, metal_code, metal_name,
               base_price, final_predicted_return, final_predicted_price,
               predicted_return_p10, predicted_return_p50, predicted_return_p90,
               predicted_price_p10, predicted_price_p50, predicted_price_p90,
               relative_strength_rank, volatility_level, risk_level,
               procurement_signal, procurement_advice, key_drivers,
               data_quality_score, model_reliability_level
        FROM market_production_forecasts
        WHERE {" AND ".join(clauses)}
        ORDER BY relative_strength_rank NULLS LAST, final_predicted_return DESC
    """
    rows = query_dataframe(sql, tuple(params))
    return [enrich_forecast_row(row) for row in rows.to_dict(orient="records")] if not rows.empty else []


def get_production_detail(
    metal_code: str,
    model_version: str | None = None,
    forecast_date: str | None = None,
    history_start_date: str | None = None,
    history_end_date: str | None = None,
):
    date_filter = ""
    forecast_params: list = [model_version or MODEL_VERSION, metal_code]
    if forecast_date:
        date_filter = "AND forecast_date = %s"
        forecast_params.append(forecast_date)
    else:
        clause, clause_params = latest_forecast_date_clause(model_version)
        date_filter = f"AND {clause}"
        forecast_params.extend(clause_params)
    history = load_history(metal_code, history_start_date, history_end_date, model_version)
    forecasts = query_dataframe(
        f"""
        SELECT forecast_date, horizon_day, metal_code, metal_name,
               base_price, final_predicted_return,
               final_predicted_price, predicted_return_p10, predicted_return_p50,
               predicted_return_p90, predicted_price_p10, predicted_price_p50,
               predicted_price_p90, relative_strength_rank, volatility_level,
               risk_level, procurement_signal,
               procurement_advice, key_drivers, data_quality_score,
               model_reliability_level
        FROM market_production_forecasts
        WHERE model_version = %s
          AND metal_code = %s
          {date_filter}
        ORDER BY horizon_day
        """,
        tuple(forecast_params),
    )
    forecast_rows = [enrich_forecast_row(row) for row in forecasts.to_dict(orient="records")] if not forecasts.empty else []
    current = next((row for row in forecast_rows if row.get("horizon_day") == 30), forecast_rows[0] if forecast_rows else {})
    current_signal = {
        "final_predicted_return_30d": current.get("final_predicted_return"),
        "final_predicted_price_30d": current.get("final_predicted_price"),
        "relative_strength_rank": current.get("relative_strength_rank"),
        "risk_level": current.get("risk_level"),
        "procurement_signal": current.get("procurement_signal"),
        "procurement_advice": current.get("procurement_advice"),
        "model_reliability_level": current.get("model_reliability_level"),
        "reliability_score": current.get("reliability_score"),
        "reliability_score_note": current.get("reliability_score_note"),
        "interval_judgement": current.get("interval_judgement"),
        "interval_width": current.get("interval_width"),
        "reliability_score_breakdown": current.get("reliability_score_breakdown"),
        "reliability_score_reasons": current.get("reliability_score_reasons"),
        "volatility_level": current.get("volatility_level"),
    }
    return {
        "metal_code": metal_code,
        "metal_name": current.get("metal_name"),
        "forecast_date": current.get("forecast_date") or forecast_date or latest_forecast_date(model_version),
        "base_price": current.get("base_price"),
        "current_signal": current_signal,
        "history": rows_to_dicts(history),
        "forecasts": forecast_rows,
    }


try:
    from fastapi import APIRouter

    router = APIRouter()

    @router.get("/api/market/production-forecasts")
    def production_forecasts(model_version: str | None = None, horizon_day: int | None = None, metal_code: str | None = None, forecast_date: str | None = None):
        return get_production_forecasts(model_version, horizon_day, metal_code, forecast_date)

    @router.get("/api/market/production-ranking")
    def production_ranking(model_version: str | None = None, forecast_date: str | None = None):
        return get_production_ranking(model_version, forecast_date)

    @router.get("/api/market/production-detail")
    def production_detail(
        metal_code: str,
        model_version: str | None = None,
        forecast_date: str | None = None,
        history_start_date: str | None = None,
        history_end_date: str | None = None,
    ):
        return get_production_detail(metal_code, model_version, forecast_date, history_start_date, history_end_date)

except ImportError:
    router = None
