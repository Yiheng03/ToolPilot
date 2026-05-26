from __future__ import annotations

from typing import Any

from fastapi import APIRouter

try:
    from market_model_v3_production_signal.api import (
        api_value,
        get_production_detail,
        get_production_forecasts,
        get_production_ranking,
        query_dataframe,
        rows_to_dicts,
        table_exists,
    )
except ModuleNotFoundError:
    from backend.market_model_v3_production_signal.api import (
        api_value,
        get_production_detail,
        get_production_forecasts,
        get_production_ranking,
        query_dataframe,
        rows_to_dicts,
        table_exists,
    )

router = APIRouter(prefix="/market", tags=["market"])


@router.get("/forecasts")
def market_forecasts(
    model_version: str | None = None,
    horizon_day: int | None = None,
    metal_code: str | None = None,
    forecast_date: str | None = None,
) -> list[dict[str, Any]]:
    return get_production_forecasts(model_version, horizon_day, metal_code, forecast_date)


@router.get("/prices")
def market_prices(
    metal_code: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    limit: int = 200,
) -> list[dict[str, Any]]:
    limit = max(1, min(limit, 1000))
    if table_exists("market_price_history"):
        return _market_price_history(metal_code, start_date, end_date, limit)
    if table_exists("normalized_market_prices"):
        return _normalized_market_prices(metal_code, start_date, end_date, limit)
    return _forecast_price_fallback(metal_code, limit)


@router.get("/production-forecasts")
def production_forecasts(
    model_version: str | None = None,
    horizon_day: int | None = None,
    metal_code: str | None = None,
    forecast_date: str | None = None,
) -> list[dict[str, Any]]:
    return get_production_forecasts(model_version, horizon_day, metal_code, forecast_date)


@router.get("/production-ranking")
def production_ranking(
    model_version: str | None = None,
    forecast_date: str | None = None,
) -> list[dict[str, Any]]:
    return get_production_ranking(model_version, forecast_date)


@router.get("/production-detail")
def production_detail(
    metal_code: str,
    model_version: str | None = None,
    forecast_date: str | None = None,
    history_start_date: str | None = None,
    history_end_date: str | None = None,
) -> dict[str, Any]:
    return get_production_detail(metal_code, model_version, forecast_date, history_start_date, history_end_date)


def _market_price_history(
    metal_code: str | None,
    start_date: str | None,
    end_date: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    clauses = ["price_date IS NOT NULL", "price IS NOT NULL"]
    params: list[Any] = []
    if metal_code:
        clauses.append("metal_code = %s")
        params.append(metal_code)
    if start_date:
        clauses.append("price_date >= %s")
        params.append(start_date)
    if end_date:
        clauses.append("price_date <= %s")
        params.append(end_date)
    params.append(limit)
    rows = query_dataframe(
        f"""
        SELECT price_date, metal_code, avg(price)::numeric(18,6) AS price
        FROM market_price_history
        WHERE {" AND ".join(clauses)}
        GROUP BY price_date, metal_code
        ORDER BY price_date DESC, metal_code
        LIMIT %s
        """,
        tuple(params),
    )
    return rows_to_dicts(rows)


def _normalized_market_prices(
    metal_code: str | None,
    start_date: str | None,
    end_date: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    clauses = ["price_date IS NOT NULL", "price IS NOT NULL", "is_available IS DISTINCT FROM false"]
    params: list[Any] = []
    if metal_code:
        clauses.append("metal_code = %s")
        params.append(metal_code)
    if start_date:
        clauses.append("price_date >= %s")
        params.append(start_date)
    if end_date:
        clauses.append("price_date <= %s")
        params.append(end_date)
    params.append(limit)
    rows = query_dataframe(
        f"""
        SELECT price_date, metal_code, avg(price)::numeric(18,6) AS price
        FROM normalized_market_prices
        WHERE {" AND ".join(clauses)}
        GROUP BY price_date, metal_code
        ORDER BY price_date DESC, metal_code
        LIMIT %s
        """,
        tuple(params),
    )
    return rows_to_dicts(rows)


def _forecast_price_fallback(metal_code: str | None, limit: int) -> list[dict[str, Any]]:
    forecasts = get_production_forecasts(metal_code=metal_code)
    return [
        {
            "price_date": row.get("forecast_date"),
            "metal_code": row.get("metal_code"),
            "price": api_value(row.get("base_price")),
            "source": "market_production_forecasts",
        }
        for row in forecasts[:limit]
    ]
