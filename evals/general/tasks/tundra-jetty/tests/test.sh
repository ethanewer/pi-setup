#!/usr/bin/env bash
# RMLab / tundra-jetty verifier.
# Runs as root after the agent finishes. /tests is mounted read-only.
# Must write the numeric reward to /logs/verifier/reward.txt.
set -uo pipefail
cd /app
reward=0

pass(){ echo "  [PASS] $1"; }
fail(){ echo "  [FAIL] $1"; }

## ---- 0) core deliverables present -----------------------------------------
required="/app/analysis.Rmd /app/analysis.ipynb /app/solver.R /app/hierarchical_model.stan \
         /app/ate.txt /app/posterior.csv /app/recovered_edges.csv /app/network_fit.csv"
for f in $required; do
  [ -f "$f" ] || { fail "missing deliverable $f"; echo "$reward" > /logs/verifier/reward.txt; exit 0; }
done
for f in /app/ate.txt /app/posterior.csv /app/recovered_edges.csv; do
  [ -s "$f" ] || { fail "$f empty or unreadable"; echo "$reward" > /logs/verifier/reward.txt; exit 0; }
done
[ -x /app/solver.R ] || { fail "/app/solver.R not executable"; echo "$reward" > /logs/verifier/reward.txt; exit 0; }
pass "all core deliverables present"

## ---- 1) rstan installed and loadable (C-4013b634) --------------------------
if R --vanilla -e 'suppressMessages(library(rstan)); cat("rstan-ok\n")' >/tmp/rstan.txt 2>&1 \
   && grep -q "rstan-ok" /tmp/rstan.txt; then
  pass "rstan loads (sampling API callable)"
else
  fail "rstan failed to load"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi

## ---- 2) Stan model is hierarchical beta-binomial w/ Jeffreys-type prior ---
STAN=/app/hierarchical_model.stan
ok=1
grep -q "binomial" "$STAN" || ok=0
grep -q "theta ~ beta" "$STAN" || ok=0
grep -q "alpha" "$STAN" && grep -q "beta" "$STAN" || ok=0
grep -Eq "0\.5\*log\(alpha\)|log\(alpha \+ beta\)" "$STAN" || ok=0
if [ "$ok" = 1 ]; then
  pass "hierarchical_model.stan valid beta-binomial + Jeffreys-type hyperprior"
else
  fail "hierarchical_model.stan missing required elements"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 3) R notebook: legacy nbformat, R kernel, loads data + DAG (C-a967e2bb)
if python3 - <<'PY'
import json, sys
j = json.load(open("/app/analysis.ipynb"))
if j.get("nbformat") != 4: sys.exit(1)
meta = j.get("metadata", {}) or {}
lang = (meta.get("language_info") or {}).get("name", "").lower()
ks   = (meta.get("kernelspec") or {}).get("language", "").lower()
if "r" not in lang and "r" not in ks: sys.exit(1)
code = "\n".join(str(c.get("source") or "") for c in j.get("cells", []) if c.get("cell_type") == "code")
if "obs.csv" not in code or "dag.json" not in code: sys.exit(1)
PY
then
  pass "analysis.ipynb is an R-kernel notebook that loads data + DAG"
else
  fail "ipynb invalid / not R / does not load data+dag"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 4) analysis.Rmd is a real R-markdown that loads data + DAG -----------
if [ -s /app/analysis.Rmd ] && grep -q "obs.csv" /app/analysis.Rmd \
   && grep -q "dag.json" /app/analysis.Rmd && grep -q '^```{r' /app/analysis.Rmd; then
  pass "analysis.Rmd loads data + DAG"
else
  fail "analysis.Rmd malformed"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 4b) analysis.Rmd genuinely executes (knitr over the object data) ----
if R --vanilla -e 'suppressMessages(knitr::knit("/app/analysis.Rmd", output="/tmp/knit_check.md", quiet=TRUE))' \
     >/tmp/knit.txt 2>&1 \
   && grep -qE "loaded [0-9]+ rows" /tmp/knit_check.md; then
  pass "analysis.Rmd executes via knitr over obs.csv + dag.json"
else
  fail "analysis.Rmd does not execute cleanly"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 5) R runtime invoked over the object data (C-4878683c) ----------------
VIS=/tmp/vis_out
rm -rf "$VIS"; mkdir -p "$VIS"
if ! Rscript --vanilla /app/solver.R /app/obs.csv /app/dag.json "$VIS" >/tmp/solv.txt 2>&1; then
  fail "solver.R not runnable in R (R runtime broken)"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi
grep -q "SOLVER_OK" /tmp/solv.txt || { fail "solver did not complete"; echo "$reward">/logs/verifier/reward.txt; exit 0; }
pass "R session executed the solver over the object data"

## ---- 6) visible case: edges, ATE (C-f1ee3a04, C-500da2a9) ------------------
exp=/tests/expected.json
[ -f "$exp" ] || { fail "missing tests/expected.json"; echo "$reward">/logs/verifier/reward.txt; exit 0; }

if python3 - "$exp" "$VIS/recovered_edges.csv" "/app/recovered_edges.csv" <<'PY'
import csv, json, sys
exp = json.load(open(sys.argv[1]))
want = [tuple(e) for e in exp["edges"]]
ok = True
for path in sys.argv[2:]:
    got = [(r["parent"].strip(), r["child"].strip()) for r in csv.DictReader(open(path))]
    if sorted(got) != sorted(want):
        ok = False
sys.exit(0 if ok else 1)
PY
then
  pass "visible-case edges recovered exactly"
else
  fail "visible-case recovered edges != expected directed edge set"
  echo "$reward">/logs/verifier/reward.txt; exit 0
fi

ate_vis=$(cat "$VIS/ate.txt")
true_ate_vis=$(python3 -c "import json;print(json.load(open('$exp'))['ate'])")
if awk -v a="$ate_vis" -v t="$true_ate_vis" 'BEGIN{exit !( (t-0.12<=a && a<=t+0.12) )}'; then
  pass "visible ATE within tolerance ($ate_vis vs $true_ate_vis)"
else
  fail "visible ATE out of tolerance ($ate_vis vs $true_ate_vis)"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 7) posterior.csv recovers group thetas (C-33fa1cfa, C-bb7cec38) ------
if python3 - <<'PY'
import csv, json
exp = json.load(open("/tests/expected.json"))
G = len(exp["theta_true"])
rows = list(csv.DictReader(open("/app/posterior.csv")))
if len(rows) < 200:
    print(0); raise SystemExit
cols = ["theta%d" % (g + 1) for g in range(G)]
if not all(c in rows[0] for c in cols):
    print(0); raise SystemExit
means = [sum(float(r[c]) for r in rows) / len(rows) for c in cols]
if not all(abs(means[g] - exp["theta_true"][g]) <= 0.15 for g in range(G)):
    print(0); raise SystemExit
print(1)
PY
then
  pass "posterior.csv theta posterior means near true group probabilities"
else
  fail "posterior.csv does not recover group thetas"; echo "$reward">/logs/verifier/reward.txt; exit 0
fi

## ---- 8) hidden generalization (edges + ATE + network coefficients) ---------
hidden_ok=1
for hdir in /tests/hidden/*; do
  [ -d "$hdir" ] || continue
  base=$(basename "$hdir")
  hout=/tmp/h_$base
  rm -rf "$hout"; mkdir -p "$hout"
  if ! Rscript --vanilla /app/solver.R "$hdir/obs.csv" "$hdir/dag.json" "$hout" \
       >/tmp/hs_$base.txt 2>&1; then
    fail "hidden $base: solver failed"; hidden_ok=0; continue
  fi
  if python3 - "$hdir/expected.json" "$hout/recovered_edges.csv" <<'PY'
import csv, json, sys
exp = json.load(open(sys.argv[1]))
want = sorted(tuple(e) for e in exp["edges"])
got = sorted((r["parent"].strip(), r["child"].strip()) for r in csv.DictReader(open(sys.argv[2])))
sys.exit(0 if got == want else 1)
PY
  then
    :
  else
    fail "hidden $base: recovered DAG edge set mismatch"; hidden_ok=0
  fi
  hate=$(cat "$hout/ate.txt")
  htrue=$(python3 -c "import json;print(json.load(open('$hdir/expected.json'))['ate'])")
  awk -v a="$hate" -v t="$htrue" 'BEGIN{exit !( (t-0.12<=a && a<=t+0.12) )}' \
    || { fail "hidden $base: ATE out of tolerance ($hate vs $htrue)"; hidden_ok=0; }
  if python3 - "$hdir/expected.json" "$hout/network_fit.csv" <<'PY'
import csv, json, sys
exp = json.load(open(sys.argv[1]))
want = set(tuple(sorted(e)) for e in exp["edges"])
got = {}
for r in csv.DictReader(open(sys.argv[2])):
    got[tuple(sorted((r["parent"].strip(), r["child"].strip())))] = float(r["coefficient"])
bad = any(e not in got or abs(got[e] - exp["coeff"]) > 0.12 for e in want)
sys.exit(1 if bad else 0)
PY
  then
    :
  else
    fail "hidden $base: recovered network coefficients out of tolerance"; hidden_ok=0
  fi
done
[ "$hidden_ok" = 1 ] && pass "all $(ls -d /tests/hidden/*/ | wc -l) hidden cases pass (edges + ATE + coefficients)"

## ---- reward ----------------------------------------------------------------
[ "$hidden_ok" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
