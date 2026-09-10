#!/bin/bash
# Verifier for wale-reef (executes-deliverable).
#
# Executes /app/run.py against the visible warehouse and against every hidden
# partition under /tests/hidden, sampling each run's peak RSS (ru_maxrss) and
# asserting the declared /app/memory_claim.json ceiling held on every run.
# Compares daily_summary.csv and report.json canonically (byte-exact) against
# the reference outputs in /tests/expected and /tests/hidden/<case>/expected,
# and opens the materialised daily_summary.parquet in a fresh DuckDB session
# to require it row-identical to the submitted daily_summary.csv. Writes exactly
# 0 or 1 to /logs/verifier/reward.txt and exits 0.
#
# Guarantee a reward on every exit path: if the script dies before writing a
# reward, the trap writes 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import csv, json, os, resource, shutil, subprocess, sys, traceback

DELIVERABLES = [
    "/app/run.py",
    "/app/output/daily_summary.csv",
    "/app/output/daily_summary.parquet",
    "/app/output/report.json",
    "/app/memory_claim.json",
]
CSV_HEADER = ("region,day,pct_tile,txns,units,amount_cents,"
              "rolling_avg_cents,running_total_cents,rank_by_txns")
REPORT_KEYS = ["total_txns", "total_units", "total_amount_cents",
               "distinct_days", "active_regions", "largest_day_amount_cents",
               "top_category", "top_tile_txns", "leaderboard"]
CEILING_MIN, CEILING_MAX = 128, 512

failures = []


def fail(msg):
    failures.append(msg)


def write_reward(value):
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write(value)


# ---- canonical byte images ------------------------------------------------

def canon_csv(path):
    """Deterministic byte image of a summary CSV: header + sorted rows."""
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    if len(rows) < 1:
        raise ValueError("empty file")
    if rows[0] != CSV_HEADER.split(","):
        raise ValueError("header %r != required header" % (rows[0],))
    lines = []
    for r in rows[1:]:
        if len(r) != 9:
            raise ValueError("row has %d fields, want 9" % len(r))
        region, day, pct = r[0], r[1], r[2]
        if not (region and day):
            raise ValueError("empty region/day")
        nums = [str(int(v)) for v in r[3:]]
        lines.append("\t".join([region, day, pct] + nums))
    lines.sort()
    return "\n".join(lines) + "\n"


def canon_json(path):
    """Deterministic byte image of report.json with strict typing."""
    with open(path) as fh:
        d = json.load(fh)
    if sorted(d.keys()) != sorted(REPORT_KEYS):
        raise ValueError("key set %r" % sorted(d.keys()))
    for k in ("total_txns", "total_units", "total_amount_cents",
              "distinct_days", "active_regions", "largest_day_amount_cents",
              "top_tile_txns"):
        v = d.get(k)
        if not isinstance(v, int) or isinstance(v, bool):
            raise ValueError("%s is not an integer: %r" % (k, v))
    if not isinstance(d.get("top_category"), str):
        raise ValueError("top_category not a string")
    lb = d.get("leaderboard")
    if not isinstance(lb, list) or len(lb) != 5:
        raise ValueError("leaderboard is not a 5-element list")
    for e in lb:
        if sorted(e.keys()) != ["amount_cents", "rank", "region"]:
            raise ValueError("leaderboard entry keys %r" % (sorted(e.keys()),))
        for k in ("rank", "amount_cents"):
            v = e.get(k)
            if not isinstance(v, int) or isinstance(v, bool):
                raise ValueError("leaderboard %s not an integer: %r" % (k, v))
        if not isinstance(e.get("region"), str):
            raise ValueError("leaderboard region not a string")
    return json.dumps(d, indent=2, sort_keys=True) + "\n"


def first_diff(a, b, max_lines=5):
    al, bl = a.splitlines(), b.splitlines()
    n = min(len(al), len(bl))
    for i in range(n):
        if al[i] != bl[i]:
            return "first canonical difference at line %d:\n  got:  %.160s\n  want: %.160s" % (
                i, al[i], bl[i])
    return "length differs: %d vs %d lines" % (len(al), len(bl))


# ---- materialised table checks -------------------------------------------

# Peak-RSS note: the wrapper below uses subprocess.run and then reads
# RUSAGE_CHILDREN.ru_maxrss. On Linux that field is the maximum RSS over the
# whole subprocess subtree (children of children included), so a pipeline
# that tries to hide its DuckDB work in a subprocess is measured anyway.

def csv_canon_rows(path):
    """Sorted canonical lines of a summary CSV (header dropped, integers
    normalised, values tab-joined), one string per row."""
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    lines = []
    for r in rows[1:]:
        if len(r) != 9:
            raise ValueError("row has %d fields, want 9" % len(r))
        nums = [str(int(v)) for v in r[3:]]
        lines.append("\t".join([r[0], r[1], r[2]] + nums))
    lines.sort()
    return lines


def parquet_canon_rows(path):
    """Sorted canonical lines of the materialised parquet table: every row
    rendered exactly like csv_canon_rows so the two must be identical."""
    import duckdb
    con = duckdb.connect()
    con.execute("SET threads=1")
    rows = con.execute(
        "SELECT region, CAST(day AS VARCHAR), CAST(pct_tile AS VARCHAR), "
        "CAST(txns AS VARCHAR), CAST(units AS VARCHAR), "
        "CAST(amount_cents AS VARCHAR), CAST(rolling_avg_cents AS VARCHAR), "
        "CAST(running_total_cents AS VARCHAR), CAST(rank_by_txns AS VARCHAR) "
        "FROM read_parquet(?)",
        [path]).fetchall()
    con.close()
    lines = ["\t".join(map(str, r)) for r in rows]
    lines.sort()
    return lines


def check_outputs(outdir, expdir, label):
    for fname, canon in (("daily_summary.csv", canon_csv),
                         ("report.json", canon_json)):
        got_path = os.path.join(outdir, fname)
        want_path = os.path.join(expdir, fname)
        if not os.path.exists(got_path):
            fail("%s: %s not produced" % (label, fname))
            continue
        if not os.path.exists(want_path):
            fail("%s: reference %s missing (broken fixture)" % (label, fname))
            continue
        try:
            got = canon(got_path)
            want = canon(want_path)
        except ValueError as e:
            fail("%s: %s invalid: %s" % (label, fname, e))
            continue
        if got != want:
            fail("%s: %s not byte-exact vs reference: %s" % (label, fname,
                                                             first_diff(got, want)))
    pq = os.path.join(outdir, "daily_summary.parquet")
    cv = os.path.join(outdir, "daily_summary.csv")
    if os.path.exists(pq) and os.path.exists(cv):
        try:
            from_pq = parquet_canon_rows(pq)
            from_cv = csv_canon_rows(cv)
        except Exception as e:
            fail("%s: materialised parquet check failed: %s" % (label, e))
            return
        if from_pq != from_cv:
            n = min(len(from_pq), len(from_cv))
            detail = "length differs: %d parquet rows vs %d csv rows" % (
                len(from_pq), len(from_cv))
            for i in range(n):
                if from_pq[i] != from_cv[i]:
                    detail = "first row difference at %d:\n      parquet: %.110s\n      csv:     %.110s" % (
                        i, from_pq[i], from_cv[i])
                    break
            fail("%s: materialised parquet is not row-identical to csv: %s"
                 % (label, detail))


# ---- measured execution ----------------------------------------------------

def run_measured(warehouse, outdir):
    shutil.rmtree(outdir, ignore_errors=True)
    code = (
        "import resource,subprocess,sys;"
        "r=subprocess.run([sys.executable,'/app/run.py',sys.argv[1],sys.argv[2]],"
        "capture_output=True,text=True);"
        "print(r.returncode);"
        "print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss);"
        "err=r.stdout[-1200:]+r.stderr[-1200:];"
        "sys.stderr.write(err)"
    )
    p = subprocess.run([sys.executable, "-c", code, warehouse, outdir],
                       capture_output=True, text=True)
    lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
    if len(lines) < 2:
        return (None, None, "runner output missing: " + p.stderr[-1200:])
    try:
        return (int(lines[0]), int(lines[1]), None)
    except ValueError:
        return (None, None, "runner output unparsable: " + p.stderr[-1200:])


# ---- main -------------------------------------------------------------------
peaks_mb = []

for p in DELIVERABLES:
    if not os.path.exists(p):
        fail("missing deliverable %s" % p)

if not os.path.isdir("/app/output"):
    fail("/app/output is not a directory")

ceiling = None
try:
    with open("/app/memory_claim.json") as fh:
        claim = json.load(fh)
    n = claim.get("ceiling_mb")
    if isinstance(n, bool) or not isinstance(n, int):
        raise ValueError("ceiling_mb is not an integer")
    ceiling = n
    if not (CEILING_MIN <= ceiling <= CEILING_MAX):
        fail("declared ceiling_mb %d outside [%d, %d]"
             % (ceiling, CEILING_MIN, CEILING_MAX))
except Exception as e:
    fail("memory_claim.json invalid: %s" % e)

if not failures:
    check_outputs("/app/output", "/tests/expected", "shipped-visible")

    vis_out = "/tmp/wr-visible"
    rc, peak, err = run_measured("/app/warehouse", vis_out)
    if rc != 0:
        fail("visible re-run failed (rc=%d): %s" % (rc or -1, err or ""))
    else:
        peaks_mb.append(round(peak / 1024.0, 1))
        check_outputs(vis_out, "/tests/expected", "visible-rerun")

    hidden_root = "/tests/hidden"
    cases = sorted(n for n in os.listdir(hidden_root)
                   if os.path.isdir(os.path.join(hidden_root, n)))
    if len(cases) < 2:
        fail("expected at least 2 hidden cases, found %d" % len(cases))
    for case in cases:
        wh = os.path.join(hidden_root, case, "warehouse")
        exp = os.path.join(hidden_root, case, "expected")
        out = "/tmp/wr-%s" % case
        if not os.path.isdir(wh) or not os.path.isdir(exp):
            fail("%s: hidden case missing warehouse/ or expected/" % case)
            continue
        rc, peak, err = run_measured(wh, out)
        if rc != 0:
            fail("%s: pipeline failed (rc=%d): %s" % (case, rc or -1, err or ""))
        else:
            peaks_mb.append(round(peak / 1024.0, 1))
            check_outputs(out, exp, case)

    if ceiling is not None and peaks_mb:
        for p in peaks_mb:
            if p > ceiling:
                fail("peak RSS %.1f MB exceeds declared ceiling %d MB" % (p, ceiling))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    if peaks_mb:
        print("measured peak RSS per run (MB): %s" % peaks_mb)
    if ceiling is not None:
        print("declared ceiling_mb: %d" % ceiling)
    write_reward("0")
else:
    print("ALL PASS: byte-exact outputs, materialised parquet consistent, "
          "peak RSS %s MB within declared ceiling %d MB" % (peaks_mb, ceiling))
    write_reward("1")
sys.exit(0)
PY