#!/bin/bash
# Verifier for flint-ember.
# Executes the /app/solve.py deliverable against the visible input and against
# each hidden case under /tests/hidden, comparing every emitted artifact to the
# committed goldens (byte-exact text, exact-cell spreadsheet map, pandas string
# column/order check). Always ends by writing /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
SOLVE=/app/solve.py

[ -f "$SOLVE" ] || { echo "0" > /logs/verifier/reward.txt; exit 0; }

PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

# check_case WORKDIR EXPECT_DIR
#   WORKDIR holds /app-style artifacts (input under WORKDIR/input, plus the six
#   produced files). EXPECT_DIR holds the goldens for that case.
#   Returns 0 if every artifact matches, nonzero otherwise.
check_case() {
  local wd="$1" ex="$2"
  python3 - "$wd" "$ex" <<'PY'
import json, os, sys
import pandas as pd
from openpyxl import load_workbook

wd, ex = sys.argv[1], sys.argv[2]
ok = True


def rf(base, rel):
    with open(os.path.join(base, rel), "rb") as f:
        return f.read()


def chk(name, got, want, extra=""):
    global ok
    if got != want:
        ok = False
        print("  mismatch in", name, extra)


def canon(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return "%.2f" % v
    return str(v)


def ledger_map(rel):
    ws = load_workbook(os.path.join(wd, rel))["ledger"]
    out = {}
    for row in ws.iter_rows():
        for c in row:
            if c.value is not None:
                out[c.coordinate] = canon(c.value)
    return out


# 1) plans.jsonl -- one schema-exact record per line, exact key order
chk("plans.jsonl", rf(wd, "plans.jsonl"), rf(ex, "plans.jsonl"))
# 2) decision.txt -- decision flags + NPV in exact output format
chk("decision.txt", rf(wd, "decision.txt"), rf(ex, "decision.txt"))

# 3) result.csv -- exact final column set/order, string-typed via pandas
try:
    g = pd.read_csv(os.path.join(wd, "result.csv"), dtype=str)
    w = pd.read_csv(os.path.join(ex, "result.csv"), dtype=str)
    if list(g.columns) != list(w.columns):
        ok = False; print("  column set/order mismatch:", list(g.columns))
    elif not g.equals(w):
        ok = False; print("  result.csv row/value mismatch")
    elif not all(not pd.api.types.is_numeric_dtype(g[c]) for c in g.columns):
        ok = False; print("  result.csv not string-typed")
except Exception as e:
    ok = False; print("  result.csv check errored:", repr(e))

# 4) answer.json -- optimal integer objective, byte-exact (no trailing newline)
chk("answer.json", rf(wd, "answer.json"), rf(ex, "answer.json"))
# 5) output/results.json -- stable schema-exact json, byte-exact
chk("output/results.json", rf(wd, "output/results.json"), rf(ex, "output/results.json"))

# 6) ledger.xlsx -- exact cell values at exact addresses
try:
    got_map = ledger_map("ledger.xlsx")
    want_map = json.load(open(os.path.join(ex, "ledger.json")))
    if got_map != want_map:
        ok = False
        print("  ledger cell mismatch (#got=%d #want=%d)" % (len(got_map), len(want_map)))
except Exception as e:
    ok = False
    print("  ledger unreadable:", repr(e))

sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail "wrong artifacts for case at $wd"
}

# Visible case: every declared deliverable must exist at its /app path.
for need in \
  /app/plans.jsonl /app/decision.txt /app/result.csv \
  /app/output/results.json /app/answer.json /app/ledger.xlsx; do
  [ -f "$need" ] || fail "missing deliverable $need"
done

# Visible-case artifacts already produced in /app (input ships in the image).
check_case /app /tests/expected

# Default-argument invocation must also succeed and reproduce /app artifacts.
if ! python3 "$SOLVE" >/dev/null 2>&1; then
  fail "default-arg invocation of solve.py failed"
else
  check_case /app /tests/expected
fi

# Hidden cases: fresh inputs + fresh salts/iterations/budget. Copy each case
# input into a writable workdir, run the delivered solve.py, compare to goldens.
for i in 1 2 3; do
  name="case$i"
  wd="/tmp/run_$name"
  rm -rf "$wd"; mkdir -p "$wd/input"
  cp /tests/hidden/$name/input/projects.csv "$wd/input/"
  cp /tests/hidden/$name/input/config.json "$wd/input/"
  if ! python3 "$SOLVE" "$wd" >/dev/null 2>&1; then
    fail "deliverable did not run on $name"; continue
  fi
  check_case "$wd" "/tests/hidden/$name/expected"
done

[ "$PASS" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt