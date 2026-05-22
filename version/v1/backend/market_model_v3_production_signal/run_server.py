from __future__ import annotations

import uvicorn
import sys
from pathlib import Path

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.server import app
else:
    from .server import app


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765)
