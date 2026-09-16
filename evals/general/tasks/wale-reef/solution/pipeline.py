#!/usr/bin/env python3
"""Analytical pipeline for a Hive-partitioned Parquet retail warehouse.

CLI: python3 pipeline.py <WAREHOUSE> <OUTDIR>

WAREHOUSE is a directory containing transactions/year=YYYY/month=MM/*.parquet
fact files with the schema (txn_id BIGINT, ts TIMESTAMP, region VARCHAR,
category VARCHAR, units INT, unit_price_cents INT, amount_cents BIGINT).
OUTDIR receives daily_summary.csv, daily_summary.parquet and report.json.

The pipeline runs out-of-core: a tight memory_limit plus a temp_directory make
DuckDB spill sorts/windows/aggregates to disk instead of RAM, so the process
peak RSS stays far below what an unconfigured session would use.
"""
import duckdb, json, os, resource, sys

WH, OUT = sys.argv[1], sys.argv[2]
PCT_TILES = 100
ROLLING_DAYS = 7

con = duckdb.connect()

# out-of-core configuration (honored by cpus=1)
con.execute("SET threads=1")
con.execute("SET memory_limit='256MB'")
_SPILL = "/tmp/duckdb-spill"
os.makedirs(_SPILL, exist_ok=True)
con.execute(f"SET temp_directory='{_SPILL}'")

fact_glob = os.path.join(WH, "transactions", "**", "*.parquet")

# ---- Stage A: fact-level windowed analysis (streams + spills out-of-core) ----
con.execute(
    """
    CREATE OR REPLACE TABLE tx_anal AS
    SELECT
        txn_id,
        region,
        day,
        category,
        units,
        amount_cents,
        NTILE(?) OVER (PARTITION BY region ORDER BY amount_cents, txn_id) AS pct_tile,
        SUM(amount_cents) OVER (PARTITION BY region ORDER BY txn_id)::BIGINT AS running_amount_cents
    FROM (
        SELECT txn_id, region, CAST(ts AS DATE) AS day, category,
               units, amount_cents
        FROM read_parquet(?)
    )
    """,
    [PCT_TILES, fact_glob],
)

# ---- Stage B: materialised per-(region, day, pct_tile) summary table ----
con.execute(
    """
    CREATE OR REPLACE TABLE summary AS
    WITH agg AS (
        SELECT region, day, pct_tile,
               COUNT(*)::BIGINT AS txns,
               SUM(units)::BIGINT AS units,
               SUM(amount_cents)::BIGINT AS amount_cents
        FROM tx_anal
        GROUP BY region, day, pct_tile
    )
    SELECT
        region, day, pct_tile, txns, units, amount_cents,
        ROUND(AVG(amount_cents) OVER (
            PARTITION BY region, pct_tile ORDER BY day
            ROWS BETWEEN ? PRECEDING AND CURRENT ROW
        ))::BIGINT AS rolling_avg_cents,
        SUM(amount_cents) OVER (
            PARTITION BY region, pct_tile ORDER BY day
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )::BIGINT AS running_total_cents,
        RANK() OVER (
            PARTITION BY region, pct_tile ORDER BY txns DESC
        )::BIGINT AS rank_by_txns
    FROM agg
    ORDER BY region, day, pct_tile
    """,
    [ROLLING_DAYS - 1],
)

os.makedirs(OUT, exist_ok=True)
con.execute(
    f"COPY (SELECT region, day, pct_tile, txns, units, amount_cents, "
    f"rolling_avg_cents, running_total_cents, rank_by_txns FROM summary "
    f"ORDER BY region, day, pct_tile) TO '{OUT}/daily_summary.parquet' "
    f"(FORMAT PARQUET, COMPRESSION ZSTD)"
)
con.execute(
    f"COPY (SELECT region, day, pct_tile, txns, units, amount_cents, "
    f"rolling_avg_cents, running_total_cents, rank_by_txns FROM summary "
    f"ORDER BY region, day, pct_tile) TO '{OUT}/daily_summary.csv' (HEADER true)"
)

# ---- Stage C: report ----
total_txns, total_units, total_amount = con.execute(
    "SELECT COUNT(*), SUM(units), SUM(amount_cents) FROM tx_anal"
).fetchone()
distinct_days = con.execute("SELECT COUNT(DISTINCT day) FROM tx_anal").fetchone()[0]
active_regions = con.execute("SELECT COUNT(DISTINCT region) FROM tx_anal").fetchone()[0]
largest_day_amount = con.execute(
    """SELECT MAX(amount_cents) FROM (
        SELECT SUM(amount_cents) AS amount_cents FROM tx_anal
        GROUP BY region, day
    )"""
).fetchone()[0]
top_tile_txns = con.execute(
    "SELECT COUNT(*) FROM tx_anal WHERE pct_tile = ?", [PCT_TILES]
).fetchone()[0]
top_category = con.execute(
    """SELECT category FROM (
        SELECT category, SUM(amount_cents) AS amt FROM tx_anal
        GROUP BY category
    ) ORDER BY amt DESC, category LIMIT 1"""
).fetchone()[0]
leaderboard = con.execute(
    """WITH g AS (
        SELECT region, SUM(amount_cents)::BIGINT AS amount_cents
        FROM tx_anal GROUP BY region
    )
    SELECT region, amount_cents,
           RANK() OVER (ORDER BY amount_cents DESC)::BIGINT AS rank
    FROM g
    ORDER BY amount_cents DESC, region
    LIMIT 5"""
).fetchall()

report = {
    "total_txns": int(total_txns),
    "total_units": int(total_units),
    "total_amount_cents": int(total_amount),
    "distinct_days": int(distinct_days),
    "active_regions": int(active_regions),
    "largest_day_amount_cents": int(largest_day_amount),
    "top_category": top_category,
    "top_tile_txns": int(top_tile_txns),
    "leaderboard": [
        {"rank": int(r[2]), "region": r[0], "amount_cents": int(r[1])}
        for r in leaderboard
    ],
}
with open(os.path.join(OUT, "report.json"), "w") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")

con.close()
print("PEAK_RSS_KB=%d" % resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
