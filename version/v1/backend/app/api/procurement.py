from __future__ import annotations

from typing import Any

from fastapi import APIRouter

try:
    from market_model_v3_production_signal.api import get_production_forecasts
except ModuleNotFoundError:
    from backend.market_model_v3_production_signal.api import get_production_forecasts

router = APIRouter(prefix="/procurement", tags=["procurement"])


@router.get("/advice")
def procurement_advice(
    metal_code: str | None = None,
    horizon_day: int | None = 30,
) -> list[dict[str, Any]]:
    rows = get_production_forecasts(horizon_day=horizon_day, metal_code=metal_code)
    return [
        {
            "metal_code": row.get("metal_code"),
            "metal_name": row.get("metal_name"),
            "horizon_day": row.get("horizon_day"),
            "procurement_signal": row.get("procurement_signal"),
            "procurement_advice": row.get("procurement_advice"),
            "risk_level": row.get("risk_level"),
            "forecast_date": row.get("forecast_date"),
            "forecast_target_date": row.get("forecast_target_date"),
        }
        for row in rows
    ]
