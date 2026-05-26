from __future__ import annotations

from fastapi import APIRouter

router = APIRouter(prefix="/tools", tags=["tools"])


@router.get("/specs")
def tool_specs() -> dict[str, list[str]]:
    return {
        "tool_types": ["end_mill", "drill", "turning_insert", "tap"],
        "materials": ["carbide", "hss", "cermet"],
        "coatings": ["uncoated", "tin", "ticn", "altin", "diamond"],
    }
