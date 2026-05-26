from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.api.market import router as market_router
from app.api.procurement import router as procurement_router
from app.api.tools import router as tools_router
from app.core.config import get_settings

settings = get_settings()
logger = logging.getLogger("toolpilot")

app = FastAPI(title="ToolPilot API", version="1.0.0")

if settings.cors_origins:
    logger.info("CORS enabled for origins: %s", settings.cors_origins)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    logger.warning("CORS_ORIGINS is empty; CORS middleware is disabled")

app.include_router(health_router, prefix="/api")
app.include_router(market_router, prefix="/api")
app.include_router(tools_router, prefix="/api")
app.include_router(procurement_router, prefix="/api")
