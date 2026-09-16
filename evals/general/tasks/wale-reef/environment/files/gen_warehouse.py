#!/usr/bin/env python3
"""Deterministic Hive-partitioned Parquet fact-table generator (wale-reef).

CLI: gen_warehouse.py <OUT_ROOT> <YEAR_MONTHS> <SEED>
  OUT_ROOT    directory in which transactions/year=YYYY/month=MM/*.parquet
              is created (OUT_ROOT itself is created if missing)
  YEAR_MONTHS comma-separated "YYYY-MM" partitions to generate
  SEED        integer; the same inputs always produce the same bytes

Environment: ROWS_PER_MONTH overrides the default row count per partition
(default 4,000,000 -> about 53 MB of ZSTD Parquet per partition, ~630 MB for
twelve partitions).

Randomness is seeded through duckdb's hash() applied to row indices, so no
RNG state is needed and generation is fully deterministic.
"""
import duckdb, os, sys
from calendar import monthrange

ROWS_PER_MONTH = int(os.environ.get("ROWS_PER_MONTH", "4000000"))

REGIONS = [
    "nord", "east", "south", "west", "central", "delta", "omega", "alpha",
    "beta", "gamma", "tau", "zeta", "eta", "thal", "irel", "ceven", "arkt",
    "bore", "chor", "dun", "ember", "fen", "gloom", "haven", "is", "jum",
    "karr", "lum", "mor", "nil", "os", "pe", "quel", "run", "sin", "tor",
]
CATS = ["appl", "auto", "baby", "book", "cloth", "elec", "garden", "home",
        "jewel", "media", "sport", "toy"]
CAT_BASE = [4999, 25999, 1499, 1299, 1999, 49999, 2499, 7999, 14999, 999,
            5999, 999]


def main() -> int:
    out_root, yms_arg, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    yms = [ym.strip() for ym in yms_arg.split(",") if ym.strip()]
    if not yms:
        print("gen_warehouse.py: no year-months given", file=sys.stderr)
        return 2
    con = duckdb.connect()
    con.execute("SET threads=1")
    os.makedirs(os.path.join(out_root, "transactions"), exist_ok=True)
    offset = 0
    regions_list = ",".join(REGIONS)
    cats_list = ",".join(CATS)
    bases_list = ",".join(str(b) for b in CAT_BASE)
    for ym in yms:
        y, m = (int(x) for x in ym.split("-"))
        ndays = monthrange(y, m)[1]
        part = os.path.join(out_root, "transactions",
                            f"year={y:04d}", f"month={m:02d}")
        os.makedirs(part, exist_ok=True)
        sql = f"""
        COPY (
          WITH t AS (
            SELECT i::UBIGINT AS i,
                   (hash(({seed}::BIGINT * 1000003) + i * 2654435761))::UBIGINT AS h1,
                   (hash(({seed}::BIGINT * 7919) + i * 40503 + 77))::UBIGINT  AS h2,
                   (hash(({seed}::BIGINT * 104729) + i * 9541 + 3))::UBIGINT   AS h3,
                   (hash(({seed}::BIGINT * 97) + i * 99991 + 55661))::UBIGINT AS h4
            FROM range({ROWS_PER_MONTH}) AS r(i)
          )
          SELECT
            (i + {offset})::BIGINT AS txn_id,
            TIMESTAMP '{y}-{m:02d}-01 00:00:00'
                + INTERVAL (i % {ndays}) DAY
                + INTERVAL (h1 % 86400) SECOND AS ts,
            (string_split('{regions_list}', ','))[1 + ((h2 % {len(REGIONS)})::BIGINT)] AS region,
            (string_split('{cats_list}', ','))[1 + ((h3 % {len(CATS)})::BIGINT)] AS category,
            (1 + h2 % 24)::INT AS units,
            ((string_split('{bases_list}', ','))[1 + ((h3 % {len(CATS)})::BIGINT)]::INT
                + h4 % 900)::INT AS unit_price_cents,
            ((1 + h2 % 24)
                * ((string_split('{bases_list}', ','))[1 + ((h3 % {len(CATS)})::BIGINT)]::INT
                   + h4 % 900))::BIGINT AS amount_cents
          FROM t
        ) TO '{part}/data.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);
        """
        con.execute(sql)
        size_mb = os.path.getsize(f"{part}/data.parquet") / 1e6
        print(f"{ym}: {size_mb:.1f} MB", flush=True)
        offset += ROWS_PER_MONTH
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
