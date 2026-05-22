from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ is None or __package__ == "":
    sys.path.append(str(Path(__file__).resolve().parents[2]))
    from backend.market_model_v3.common import connect, ensure_tables, log, query_dataframe, write_json
else:
    from .common import connect, ensure_tables, log, query_dataframe, write_json


PAIRS = [("CU", "AL"), ("NI", "CO"), ("W", "CU"), ("W", "AL"), ("CO", "CU"), ("NI", "CU")]


def load_quant_features() -> pd.DataFrame:
    sql = """
        SELECT metal_code, price_date, close_price,
               return_7d, return_30d, return_90d,
               target_return_7d, target_return_30d, target_return_90d
        FROM market_quant_features
        ORDER BY metal_code, price_date
    """
    return query_dataframe(sql)


def build_pair_features(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    frames = []
    skipped: dict[str, str] = {}
    existing = set(df["metal_code"].unique())
    for base, compare in PAIRS:
        pair_key = f"{base}/{compare}"
        if base not in existing or compare not in existing:
            skipped[pair_key] = f"missing metal: {', '.join([c for c in [base, compare] if c not in existing])}"
            continue
        base_df = df[df["metal_code"] == base].copy()
        compare_df = df[df["metal_code"] == compare].copy()
        merged = base_df.merge(compare_df, on="price_date", suffixes=("_base", "_compare"))
        if len(merged) < 30:
            skipped[pair_key] = f"overlap_rows={len(merged)} < 30"
            continue
        out = pd.DataFrame(
            {
                "price_date": merged["price_date"],
                "base_metal_code": base,
                "compare_metal_code": compare,
                "base_price": merged["close_price_base"],
                "compare_price": merged["close_price_compare"],
                "price_ratio": merged["close_price_base"] / merged["close_price_compare"].replace(0, np.nan),
                "spread_return_7d": merged["return_7d_base"] - merged["return_7d_compare"],
                "spread_return_30d": merged["return_30d_base"] - merged["return_30d_compare"],
                "spread_return_90d": merged["return_90d_base"] - merged["return_90d_compare"],
                "target_pair_return_7d": merged["target_return_7d_base"] - merged["target_return_7d_compare"],
                "target_pair_return_30d": merged["target_return_30d_base"] - merged["target_return_30d_compare"],
                "target_pair_return_90d": merged["target_return_90d_base"] - merged["target_return_90d_compare"],
            }
        )
        frames.append(out)
    result = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
    report = {
        "requested_pairs": [f"{a}/{b}" for a, b in PAIRS],
        "generated_pairs": sorted(result.apply(lambda r: f"{r['base_metal_code']}/{r['compare_metal_code']}", axis=1).unique().tolist()) if not result.empty else [],
        "skipped_pairs": skipped,
        "row_count": int(len(result)),
    }
    return result, report


def upsert_pair_features(df: pd.DataFrame) -> int:
    if df.empty:
        return 0
    columns = [
        "price_date", "base_metal_code", "compare_metal_code", "base_price", "compare_price",
        "price_ratio", "spread_return_7d", "spread_return_30d", "spread_return_90d",
        "target_pair_return_7d", "target_pair_return_30d", "target_pair_return_90d",
    ]
    clean = df[columns].replace({np.nan: None})
    update_cols = [c for c in columns if c not in {"price_date", "base_metal_code", "compare_metal_code"}]
    sql = f"""
        INSERT INTO market_pair_features ({", ".join(columns)})
        VALUES ({", ".join(["%s"] * len(columns))})
        ON CONFLICT (price_date, base_metal_code, compare_metal_code) DO UPDATE SET
        {", ".join([f"{c}=EXCLUDED.{c}" for c in update_cols])}
    """
    rows = [tuple(row) for row in clean.itertuples(index=False, name=None)]
    with connect() as conn:
        with conn.cursor() as cur:
            cur.executemany(sql, rows)
        conn.commit()
    return len(rows)


def main() -> dict:
    ensure_tables()
    df = load_quant_features()
    pair_df, report = build_pair_features(df)
    report["upserted_rows"] = upsert_pair_features(pair_df)
    write_json(Path(__file__).resolve().parent / "pair_feature_report.json", report)
    log(f"pair features upserted: {report['upserted_rows']}; skipped={report['skipped_pairs']}")
    return report


if __name__ == "__main__":
    main()
