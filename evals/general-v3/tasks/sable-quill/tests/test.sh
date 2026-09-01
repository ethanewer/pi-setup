#!/bin/bash
# sable-quill verifier. Regex-checks the obliged entry-point names at line
# start in /app/tidekit.R, then re-loads the module in fresh R processes and
# exercises tide_estimate on hidden (n, rate) cases, the error edge case,
# reproducibility, and tide_selftest(); also checks the recorded selftest.log.
set -u
mkdir -p /logs/verifier
REWARD=0
LOG(){ echo "$*"; }
FAIL=0
note_fail(){ LOG "FAIL: $*"; FAIL=1; }

MODULE=/app/tidekit.R
SELFLOG=/app/selftest.log

[ -f "$MODULE" ] || { LOG "DELIVERABLE $MODULE missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }
[ -s "$SELFLOG" ] || note_fail "selftest.log missing/empty"
grep -q 'PASS' "$SELFLOG" 2>/dev/null || note_fail "selftest.log lacks PASS"

# obliged entry points must be defined at line start (regex on the source)
grep -Eq '^tide_estimate[[:space:]]*(<-|=)?[[:space:]]*function' "$MODULE" \
  || note_fail "tide_estimate not defined at line start"
grep -Eq '^tide_selftest[[:space:]]*(<-|=)?[[:space:]]*function' "$MODULE" \
  || note_fail "tide_selftest not defined at line start"

# hidden numeric cases (fresh R process per case); params.json is a flat
# object with keys n, rate, abs_tol (null = finite-only) and expect_error.
json_val() { sed -n 's/.*"'$2'"[[:space:]]*:[[:space:]]*\([^,}]*\)[,}].*/\1/p' "$1" | head -1; }
if [ "$FAIL" -eq 0 ]; then
  for p in /tests/hidden/*/params.json; do
    [ -f "$p" ] || continue
    n="$(json_val "$p" n)"; rate="$(json_val "$p" rate)"
    abst="$(json_val "$p" abs_tol)"; experr="$(json_val "$p" expect_error)"
    out="$(Rscript -e ' 
      a <- commandArgs(trailingOnly = TRUE)
      n <- as.numeric(a[1]); rate <- as.numeric(a[2])
      abst <- if (a[3] == "null" || a[3] == "") NULL else as.numeric(a[3])
      experr <- identical(a[4], "true")
      source("/app/tidekit.R")
      res <- tryCatch(
        tide_estimate(n, rate = rate),
        error = function(e) paste0("ERROR:", conditionMessage(e)))
      if (experr) {
        if (is.character(res) && startsWith(res, "ERROR:")) {
          cat("case-ok error-raised")
        } else {
          cat("case-bad expected-error-got:", format(res))
        }
      } else {
        if (is.character(res)) {
          cat("case-bad unexpected-error:", res)
        } else if (length(res) != 1 || !is.finite(res)) {
          cat("case-bad non-finite/non-scalar:", format(res))
        } else if (!is.null(abst) && abs(res - 1/rate) > abst) {
          cat(sprintf("case-bad estimate %.6f off target %.6f", res, 1/rate))
        } else {
          cat("case-ok", format(res))
        }
      }
    ' "$n" "$rate" "$abst" "$experr" 2>&1)"
    case "$out" in
      case-ok*) LOG "hidden $(basename "$(dirname "$p")"): PASS ($out)" ;;
      *) note_fail "hidden case $p: $out" ; break ;;
    esac
  done
fi

# reproducibility: two identical calls must agree exactly
if [ "$FAIL" -eq 0 ]; then
  Rscript -e '
    source("/app/tidekit.R")
    a <- tide_estimate(500, rate = 0.4)
    b <- tide_estimate(500, rate = 0.4)
    if (!is.finite(a) || !identical(a, b)) quit(status = 1)
  ' 2>/dev/null || note_fail "tide_estimate not reproducible/not finite"
fi

# the grader re-runs the self-test itself: exit 0 and PASS on stdout
if [ "$FAIL" -eq 0 ]; then
  st_out="$(Rscript -e 'source("/app/tidekit.R"); tide_selftest()' 2>/dev/null)"
  st_rc=$?
  [ $st_rc -eq 0 ] || note_fail "tide_selftest exit status $st_rc"
  echo "$st_out" | grep -q 'PASS' || note_fail "tide_selftest output lacks PASS"
fi

if [ "$FAIL" -eq 0 ]; then
  REWARD=1
  LOG "ALL CHECKS PASS"
fi
echo "$REWARD" > /logs/verifier/reward.txt
exit 0
