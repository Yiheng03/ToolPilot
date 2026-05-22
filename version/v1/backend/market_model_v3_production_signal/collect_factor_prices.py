from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3_production_signal.common import (
        INDUSTRIAL_FACTORS,
        MODULE_DIR,
        REQUESTED_FACTORS,
        TOOLSQL_DIR,
        connect,
        ensure_tables,
        log,
        query_dataframe,
        write_json,
    )
else:
    from .common import (
        INDUSTRIAL_FACTORS,
        MODULE_DIR,
        REQUESTED_FACTORS,
        TOOLSQL_DIR,
        connect,
        ensure_tables,
        log,
        query_dataframe,
        write_json,
    )


CSV_ALIASES = {
    "WTI": {"wti", "cl", "crude", "crude_oil", "oil_wti"},
    "BRENT": {"brent", "bz", "brent_oil"},
    "NATURAL_GAS": {"natural_gas", "natgas", "ng"},
    "GOLD": {"gold", "xau", "xauusd"},
    "SILVER": {"silver", "xag", "xagusd"},
    "DXY": {"dxy", "dollar_index", "usdx"},
    "USD_CNY": {"usd_cny", "usdcny", "cny", "usd/rmb"},
    "SP500": {"sp500", "s&p500", "s_and_p_500", "gspc"},
    "NASDAQ": {"nasdaq", "ixic", "ndx"},
    "CSI300": {"csi300", "沪深300"},
    "SHANGHAI_INDEX": {"shanghai_index", "sse", "000001.ss", "上证指数"},
}

DATE_COLUMNS = ["price_date", "date", "trade_date", "datetime", "time"]
PRICE_COLUMNS = ["close_price", "close", "price", "last", "adj_close", "settle"]
SYMBOL_COLUMNS = ["factor_code", "symbol", "ticker", "code", "source_symbol", "name"]
WIDE_CSV_COLUMNS = {
    "WTI": {"WTI CRUDE", "WTI", "CRUDE OIL"},
    "BRENT": {"BRENT CRUDE", "BRENT"},
    "NATURAL_GAS": {"NATURAL GAS"},
    "GOLD": {"GOLD"},
    "SILVER": {"SILVER"},
    "CU": {"COPPER"},
    "AL": {"ALUMINIUM", "ALUMINUM"},
    "NI": {"NICKEL"},
    "ZN": {"ZINC"},
}


def load_industrial_factors_from_quant_features() -> tuple[pd.DataFrame, dict]:
    df = query_dataframe(
        """
        SELECT metal_code AS factor_code,
               metal_name AS factor_name,
               price_date,
               close_price::float8 AS close_price,
               'database:market_quant_features' AS source_provider,
               metal_code AS source_symbol
        FROM market_quant_features
        WHERE close_price IS NOT NULL
        ORDER BY metal_code, price_date
        """
    )
    if df.empty:
        return pd.DataFrame(), {code: "market_quant_features has no rows" for code in INDUSTRIAL_FACTORS}
    df = df[df["factor_code"].isin(INDUSTRIAL_FACTORS)].copy()
    df["factor_type"] = "industrial_metal"
    for code, (name, _) in INDUSTRIAL_FACTORS.items():
        df.loc[df["factor_code"].eq(code) & df["factor_name"].isna(), "factor_name"] = name
    missing = {
        code: "not found in market_quant_features"
        for code in INDUSTRIAL_FACTORS
        if code not in set(df["factor_code"].unique())
    }
    return df, missing


def normalize_name(value: object) -> str:
    return str(value or "").strip().lower().replace("-", "_").replace(" ", "_")


def detect_column(columns: list[str], candidates: list[str]) -> str | None:
    lower = {c.lower(): c for c in columns}
    for candidate in candidates:
        if candidate.lower() in lower:
            return lower[candidate.lower()]
    return None


def match_factor_from_path_or_symbol(path: Path, symbol_value: object = None) -> str | None:
    text = normalize_name(path.stem)
    if symbol_value is not None:
        text += " " + normalize_name(symbol_value)
    for factor_code, aliases in CSV_ALIASES.items():
        if normalize_name(factor_code) in text or any(alias in text for alias in aliases):
            return factor_code
    return None


def load_external_factors_from_csv() -> tuple[pd.DataFrame, dict]:
    frames = []
    skipped: dict[str, str] = {}
    files = [
        p
        for p in TOOLSQL_DIR.rglob("*.csv")
        if ".git" not in p.parts and "__pycache__" not in p.parts and p.is_file()
    ]
    for path in files:
        try:
            sample = pd.read_csv(path, nrows=5)
            date_col = detect_column(list(sample.columns), DATE_COLUMNS)
            price_col = detect_column(list(sample.columns), PRICE_COLUMNS)
            symbol_col = detect_column(list(sample.columns), SYMBOL_COLUMNS)
            if not date_col or not price_col:
                continue
            usecols = [date_col, price_col] + ([symbol_col] if symbol_col else [])
            raw = pd.read_csv(path, usecols=list(dict.fromkeys(usecols)))
            if symbol_col:
                raw["_factor_code"] = raw[symbol_col].map(lambda v: match_factor_from_path_or_symbol(path, v))
            else:
                raw["_factor_code"] = match_factor_from_path_or_symbol(path)
            raw = raw[raw["_factor_code"].notna()].copy()
            if raw.empty:
                continue
            raw["price_date"] = pd.to_datetime(raw[date_col], errors="coerce").dt.date
            raw["close_price"] = pd.to_numeric(raw[price_col], errors="coerce")
            raw = raw.dropna(subset=["price_date", "close_price", "_factor_code"])
            raw = raw[raw["close_price"] > 0].copy()
            if raw.empty:
                continue
            raw["factor_code"] = raw["_factor_code"]
            raw["factor_name"] = raw["factor_code"].map(lambda c: REQUESTED_FACTORS[c][0])
            raw["factor_type"] = raw["factor_code"].map(lambda c: REQUESTED_FACTORS[c][1])
            raw["source_provider"] = f"csv:{path.relative_to(TOOLSQL_DIR)}"
            raw["source_symbol"] = raw["factor_code"]
            frames.append(raw[["factor_code", "factor_name", "factor_type", "price_date", "close_price", "source_provider", "source_symbol"]])
        except Exception as exc:  # keep collection tolerant; report exact file failures.
            skipped[str(path)] = str(exc)
    result = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    return result, skipped


def load_wide_external_factors_from_csv() -> tuple[pd.DataFrame, dict]:
    frames = []
    skipped: dict[str, str] = {}
    files = [
        p
        for p in TOOLSQL_DIR.rglob("*.csv")
        if ".git" not in p.parts and "__pycache__" not in p.parts and p.is_file()
    ]
    for path in files:
        try:
            header = pd.read_csv(path, nrows=0)
            date_col = detect_column(list(header.columns), DATE_COLUMNS)
            if not date_col:
                continue
            normalized_cols = {normalize_name(c): c for c in header.columns}
            matched: dict[str, str] = {}
            for factor_code, candidates in WIDE_CSV_COLUMNS.items():
                for candidate in candidates:
                    col = normalized_cols.get(normalize_name(candidate))
                    if col:
                        matched[factor_code] = col
                        break
            if not matched:
                continue
            raw = pd.read_csv(path, usecols=[date_col, *matched.values()])
            raw["price_date"] = pd.to_datetime(raw[date_col], errors="coerce").dt.date
            for factor_code, col in matched.items():
                sub = raw[["price_date", col]].copy()
                sub["close_price"] = pd.to_numeric(sub[col], errors="coerce")
                sub = sub.dropna(subset=["price_date", "close_price"])
                sub = sub[sub["close_price"] > 0].copy()
                if sub.empty:
                    continue
                sub["factor_code"] = factor_code
                sub["factor_name"] = REQUESTED_FACTORS[factor_code][0]
                sub["factor_type"] = REQUESTED_FACTORS[factor_code][1]
                sub["source_provider"] = f"csv-wide:{path.relative_to(TOOLSQL_DIR)}"
                sub["source_symbol"] = col
                frames.append(sub[["factor_code", "factor_name", "factor_type", "price_date", "close_price", "source_provider", "source_symbol"]])
        except Exception as exc:
            skipped[str(path)] = str(exc)
    result = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    return result, skipped


def upsert_factor_prices(df: pd.DataFrame) -> int:
    if df.empty:
        return 0
    columns = [
        "factor_code",
        "factor_name",
        "factor_type",
        "price_date",
        "close_price",
        "source_provider",
        "source_symbol",
    ]
    clean = df[columns].copy()
    clean["close_price"] = pd.to_numeric(clean["close_price"], errors="coerce")
    clean = clean.replace({np.nan: None}).dropna(subset=["factor_code", "price_date", "close_price"])
    rows = [tuple(row) for row in clean.itertuples(index=False, name=None)]
    sql = f"""
        INSERT INTO market_factor_prices ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (factor_code, price_date, source_provider) DO UPDATE SET
          factor_name = EXCLUDED.factor_name,
          factor_type = EXCLUDED.factor_type,
          close_price = EXCLUDED.close_price,
          source_symbol = EXCLUDED.source_symbol,
          updated_at = now()
    """
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    industrial, industrial_missing = load_industrial_factors_from_quant_features()
    external, csv_skipped = load_external_factors_from_csv()
    wide_external, wide_csv_skipped = load_wide_external_factors_from_csv()
    csv_skipped.update(wide_csv_skipped)
    frames = [df for df in [industrial, external, wide_external] if not df.empty]
    combined = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    if not combined.empty:
        combined = (
            combined.sort_values(["factor_code", "price_date", "source_provider"])
            .drop_duplicates(["factor_code", "price_date", "source_provider"], keep="last")
        )
    upserted = upsert_factor_prices(combined)
    present = sorted(combined["factor_code"].unique().tolist()) if not combined.empty else []
    missing = {}
    for code in REQUESTED_FACTORS:
        if code not in present:
            missing[code] = industrial_missing.get(code) or "no matching existing database rows or CSV source found"
    report = {
        "upserted_rows": upserted,
        "present_factors": present,
        "missing_factors": missing,
        "csv_file_errors": csv_skipped,
        "source_policy": "database market_quant_features plus existing CSV files only; no synthetic price backfill",
    }
    write_json(MODULE_DIR / "factor_price_collection_report.json", report)
    log(f"factor prices upserted: {upserted}; present={present}; missing={list(missing)}")
    return report


if __name__ == "__main__":
    main()
