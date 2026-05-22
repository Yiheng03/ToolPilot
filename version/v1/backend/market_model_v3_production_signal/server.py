from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse

from .api import router


FRONTEND_PATH = Path(__file__).resolve().parents[1] / "frontend" / "market_production_dashboard.html"

app = FastAPI(title="ToolPilot Market Production Signal API")
app.include_router(router)


@app.get("/")
def index():
    return FileResponse(FRONTEND_PATH)


@app.get("/market-forecast")
def market_forecast():
    return FileResponse(FRONTEND_PATH)

