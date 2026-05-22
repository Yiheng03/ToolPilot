import json
import mimetypes
import os
import re
from datetime import date, datetime
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import psycopg
from psycopg.rows import dict_row


BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent
TOOLSQL_DIR = PROJECT_DIR.parent
STATIC_DIR = BASE_DIR / "static"
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def load_env_file(path: Path) -> None:
    if not path.exists():
        return

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


load_env_file(TOOLSQL_DIR / ".env")
load_env_file(PROJECT_DIR / ".env")


def get_connection():
    return psycopg.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "postgres"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD"),
        row_factory=dict_row,
    )


def to_jsonable(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def rows_to_jsonable(rows):
    return [
        {key: to_jsonable(value) for key, value in row.items()}
        for row in rows
    ]


def query_all(sql, params=()):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return rows_to_jsonable(cur.fetchall())


def query_one(sql, params=()):
    rows = query_all(sql, params)
    return rows[0] if rows else None


def require_param(params, name):
    value = params.get(name, [""])[0].strip()
    if not value:
        raise ValueError(f"Missing required parameter: {name}")
    return value


def optional_date(params, name):
    value = params.get(name, [""])[0].strip()
    if value and not DATE_RE.match(value):
        raise ValueError(f"Invalid date parameter: {name}")
    return value or None


def latest_forecast_batch():
    return query_one(
        """
        SELECT forecast_batch_id
        FROM market_forecast_model_runs
        WHERE run_status = 'success'
        ORDER BY finished_at DESC NULLS LAST, started_at DESC
        LIMIT 1;
        """
    )


def normalize_forecast_curve(rows):
    if not rows:
        return rows

    best_by_day = {}
    for row in rows:
        horizon_day = int(row["horizon_day"])
        curve_type = row.get("curve_type")
        if not curve_type:
            curve_type = (
                "direct_horizon_forecast_point"
                if row.get("forecast_method") == "direct_horizon_lightgbm"
                else "interpolated_daily_curve_point"
            )
            row["curve_type"] = curve_type
        row["anchor_source"] = row.get("anchor_source") or "direct_horizon_model_7_30_90"
        row["tooltip_label"] = (
            "模型直接预测点"
            if curve_type == "direct_horizon_forecast_point"
            else "插值生成曲线点"
        )

        existing = best_by_day.get(horizon_day)
        if existing is None or curve_type == "direct_horizon_forecast_point":
            best_by_day[horizon_day] = row

    return [best_by_day[day] for day in sorted(best_by_day)]


def handle_api(path, params):
    if path == "/api/market/health":
        return {
            "status": "ok",
            "data_source": "PostgreSQL",
            "tables": {
                "market_price_history": query_one("SELECT COUNT(*) AS count FROM market_price_history;"),
                "market_forecast_model_runs": query_one("SELECT COUNT(*) AS count FROM market_forecast_model_runs;"),
                "market_price_forecasts": query_one("SELECT COUNT(*) AS count FROM market_price_forecasts;"),
            },
        }

    if path == "/api/market/metals":
        return query_all(
            """
            SELECT DISTINCT metal_code, metal_name
            FROM market_price_history
            WHERE metal_code IS NOT NULL
            ORDER BY metal_code;
            """
        )

    if path == "/api/market/forecast-batches/latest":
        batch = latest_forecast_batch()
        return batch or {"forecast_batch_id": None}

    if path == "/api/market/forecast-batches":
        rows = query_all(
            """
            SELECT
                forecast_batch_id,
                COUNT(DISTINCT metal_code) AS metal_count,
                MIN(started_at) AS started_at,
                MAX(finished_at) AS finished_at,
                BOOL_AND(run_status = 'success') AS all_success
            FROM market_forecast_model_runs
            GROUP BY forecast_batch_id
            ORDER BY MAX(finished_at) DESC NULLS LAST, MIN(started_at) DESC
            LIMIT 20;
            """
        )
        return rows

    if path == "/api/market/history":
        metal_code = require_param(params, "metal_code").upper()
        start_date = optional_date(params, "start_date")
        end_date = optional_date(params, "end_date")
        if not start_date or not end_date:
            raise ValueError("start_date and end_date are required")
        return query_all(
            """
            SELECT
                metal_code,
                metal_name,
                price_date,
                price,
                change_pct,
                currency,
                unit,
                source_provider,
                source_type,
                price_type
            FROM market_price_history
            WHERE metal_code = %s
              AND price_date BETWEEN %s AND %s
            ORDER BY price_date ASC;
            """,
            (metal_code, start_date, end_date),
        )

    if path == "/api/market/forecasts":
        metal_code = require_param(params, "metal_code").upper()
        forecast_batch_id = params.get("forecast_batch_id", [""])[0].strip()
        if not forecast_batch_id:
            batch = latest_forecast_batch()
            forecast_batch_id = batch["forecast_batch_id"] if batch else ""
        start_date = optional_date(params, "start_date")
        end_date = optional_date(params, "end_date")
        if not forecast_batch_id:
            return []
        if not start_date or not end_date:
            raise ValueError("start_date and end_date are required")
        rows = query_all(
            """
            SELECT
                forecast_batch_id,
                metal_code,
                metal_name,
                base_price_date,
                base_price,
                forecast_date,
                horizon_day,
                predicted_return_pct,
                predicted_price,
                lower_bound_price,
                upper_bound_price,
                confidence_level,
                trend_label,
                model_name,
                model_version,
                forecast_method,
                COALESCE(curve_type, 'direct_horizon_forecast_point') AS curve_type,
                anchor_source
            FROM market_price_forecasts
            WHERE metal_code = %s
              AND forecast_batch_id = %s
              AND forecast_date BETWEEN %s AND %s
            ORDER BY forecast_date ASC;
            """,
            (metal_code, forecast_batch_id, start_date, end_date),
        )
        return normalize_forecast_curve(rows)

    if path == "/api/market/forecast-summary":
        metal_code = require_param(params, "metal_code").upper()
        forecast_batch_id = params.get("forecast_batch_id", [""])[0].strip()
        if not forecast_batch_id:
            batch = latest_forecast_batch()
            forecast_batch_id = batch["forecast_batch_id"] if batch else ""
        if not forecast_batch_id:
            return []
        return query_all(
            """
            SELECT
                horizon_day,
                forecast_date,
                predicted_price,
                predicted_return_pct,
                base_price,
                ROUND(((predicted_price / NULLIF(base_price, 0) - 1) * 100)::numeric, 4) AS cumulative_change_pct,
                trend_label,
                forecast_method
            FROM market_price_forecasts
            WHERE metal_code = %s
              AND forecast_batch_id = %s
              AND horizon_day IN (7, 30, 90)
            ORDER BY horizon_day ASC;
            """,
            (metal_code, forecast_batch_id),
        )

    if path == "/api/market/model-run":
        metal_code = require_param(params, "metal_code").upper()
        forecast_batch_id = params.get("forecast_batch_id", [""])[0].strip()
        if not forecast_batch_id:
            batch = latest_forecast_batch()
            forecast_batch_id = batch["forecast_batch_id"] if batch else ""
        if not forecast_batch_id:
            return None
        return query_one(
            """
            SELECT
                forecast_batch_id,
                metal_code,
                metal_name,
                model_name,
                model_version,
                train_rows,
                test_rows,
                mae_price,
                rmse_price,
                mape_price,
                direction_accuracy,
                run_status,
                started_at,
                finished_at
            FROM market_forecast_model_runs
            WHERE metal_code = %s
              AND forecast_batch_id = %s
            ORDER BY started_at DESC
            LIMIT 1;
            """,
            (metal_code, forecast_batch_id),
        )

    raise FileNotFoundError(path)


class MarketForecastHandler(BaseHTTPRequestHandler):
    server_version = "ToolPilotMarketForecast/0.1"

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") if parsed.path != "/" else "/"
        params = parse_qs(parsed.query)

        try:
            if path.startswith("/api/"):
                self.send_json(handle_api(path, params))
                return

            if path == "/":
                self.send_response(302)
                self.send_header("Location", "/market-forecast")
                self.end_headers()
                return

            if path == "/market-forecast":
                self.send_file(STATIC_DIR / "index.html")
                return

            if path.startswith("/static/"):
                relative = path.removeprefix("/static/").lstrip("/")
                target = (STATIC_DIR / relative).resolve()
                if STATIC_DIR.resolve() not in target.parents and target != STATIC_DIR.resolve():
                    raise FileNotFoundError(path)
                self.send_file(target)
                return

            raise FileNotFoundError(path)
        except FileNotFoundError:
            self.send_json({"error": "not_found", "detail": path}, status=404)
        except ValueError as exc:
            self.send_json({"error": "bad_request", "detail": str(exc)}, status=400)
        except Exception as exc:
            self.send_json(
                {"error": "server_error", "detail": f"{type(exc).__name__}: {exc}"},
                status=500,
            )

    def send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path: Path):
        if not path.exists() or not path.is_file():
            raise FileNotFoundError(str(path))
        content = path.read_bytes()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if path.suffix == ".js":
            content_type = "application/javascript"
        if path.suffix == ".css":
            content_type = "text/css"
        self.send_response(200)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format, *args):
        print("%s - %s" % (self.address_string(), format % args))


if __name__ == "__main__":
    host = os.getenv("MARKET_FORECAST_HOST", "127.0.0.1")
    port = int(os.getenv("MARKET_FORECAST_PORT", "8765"))
    server = ThreadingHTTPServer((host, port), MarketForecastHandler)
    print(f"ToolPilot market forecast page: http://{host}:{port}/market-forecast")
    print("Data source: PostgreSQL")
    server.serve_forever()
