#!/bin/bash
# Verifier for saffron-dial: enforces the plug-in contract — required entry-point
# names discovered by line-anchored regex in /app/diversity.R, then EXECUTES the
# deliverable functions on hidden survey cases (fresh R process per case) and
# re-runs the self-test. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import re
import subprocess
import sys

SRC = "/app/diversity.R"
LOG = "/app/selftest.log"

failures = []

# ---- deliverable presence + entry-point discovery (line-anchored regex) ----
if not os.path.isfile(SRC):
    failures.append("missing /app/diversity.R")
    src = ""
else:
    with open(SRC, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
for name in ("reef_diversity", "reef_selftest"):
    if not re.search(r"(?m)^%s\b" % re.escape(name), src):
        failures.append("entry point %r not found at start of a line in diversity.R" % name)

if not os.path.isfile(LOG) or os.path.getsize(LOG) == 0:
    failures.append("selftest.log missing or empty")
else:
    with open(LOG, encoding="utf-8", errors="replace") as fh:
        ltext = fh.read()
    if "PASS" not in ltext:
        failures.append("selftest.log lacks PASS token")

# ---- hidden case runner ----
def run_r(counts, base):
    """Run reef_diversity in a fresh R process. Returns (exit, stdout)."""
    r_expr = (
        'source("/app/diversity.R"); '
        'a <- commandArgs(TRUE); if (length(a) > 0 && a[1] == "--") a <- a[-1]; '
        'counts <- if (nzchar(a[1])) as.numeric(strsplit(a[1], ",", fixed=TRUE)[[1]]) else numeric(0); '
        'base <- if (a[2] == "e") exp(1) else as.numeric(a[2]); '
        'cat(format(reef_diversity(counts, base), digits=17, scientific=FALSE))'
    )
    r = subprocess.run(
        ["Rscript", "-e", r_expr, "--", counts, base],
        capture_output=True, text=True, timeout=120,
    )
    return r.returncode, r.stdout.strip()


hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(d for d in os.listdir(hidden) if os.path.isdir(os.path.join(hidden, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base_dir = os.path.join(hidden, c)
        try:
            with open(os.path.join(base_dir, "input.json")) as fh:
                inp = json.load(fh)
            with open(os.path.join(base_dir, "expected.json")) as fh:
                exp = json.load(fh)
        except Exception:
            failures.append("hidden '%s': unreadable case files" % c)
            continue
        try:
            if inp.get("kind") == "selftest":
                r = subprocess.run(
                    ["Rscript", "-e", 'source("/app/diversity.R"); reef_selftest()'],
                    capture_output=True, text=True, timeout=120,
                )
                if r.returncode != 0 or "PASS" not in r.stdout:
                    failures.append("hidden '%s': selftest rerun failed (rc=%d)" % (c, r.returncode))
                continue
            counts = str(inp.get("counts", ""))
            base = str(inp.get("base", "2"))
            rc, out = run_r(counts, base)
            if exp.get("error"):
                if rc == 0:
                    failures.append("hidden '%s': expected an R error, got success" % c)
                continue
            if rc != 0:
                failures.append("hidden '%s': R error on valid input" % c)
                continue
            got = float(out.splitlines()[-1])
            want = float(exp["value"])
            if not (abs(got - want) <= 1e-6 * max(1.0, abs(want))):
                failures.append("hidden '%s': got %r want %r" % (c, got, want))
        except Exception as e:
            failures.append("hidden '%s': %s" % (c, e))
else:
    failures.append("hidden cases directory missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
