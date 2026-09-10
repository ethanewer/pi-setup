#!/bin/bash
#
# Verifier for tasks/wale-ferry (executes-deliverable).
#
# Resets the live MariaDB to its byte-identical pristine seed, confirms the
# shipped schema really filesorts, applies the agent's /app/migration.sql
# twice (idempotency), then grades:
#   - EXPLAIN of 3 hidden query files: non-NULL key whose leading columns are
#     the rollup dimensions of the workload, no 'filesort' in Extra;
#   - results of the hidden queries and the 4 visible workload queries against
#     golden TSV sets;
#   - the dependent view vw_region_performance resolves and returns golden rows;
#   - /app/explain_report.tsv equals the plans the verifier re-derives.
# Reward is binary and written on every exit path.
set -u

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
mkdir -p /logs/verifier

SOCK=/run/mysqld/mysqld.sock
H=/tests/hidden
MDB="mariadb --socket=$SOCK"
FAILS=""

fail(){ echo "FAIL: $*"; FAILS="$FAILS $*"; }
pass(){ echo "PASS: $*"; }

finalize() {
  if [ -z "$FAILS" ]; then
    echo "wale-ferry verifier: ALL CHECKS PASSED"
    echo 1 > /logs/verifier/reward.txt
  else
    echo "wale-ferry verifier FAILED:$FAILS" >&2
    echo 0 > /logs/verifier/reward.txt
  fi
}

# explain_one <queryfile> -> "select_type\ttype\tkey\tExtra" of the first row
explain_one() {
  timeout 120 $MDB --batch --column-names=0 analytics \
    -e "EXPLAIN $(cat "$1")" 2>/dev/null \
    | awk -F '\t' '{print $2"\t"$4"\t"$6"\t"$10}' | head -1
}

run_q() { # run_q <queryfile> <outfile> -> 0 on success
  timeout 300 $MDB --batch --raw analytics < "$1" > "$2" 2>/dev/null
}

plan_ok() { # plan_ok <label> <line> -> 0 when a real plan without filesort
  local label=$1 line=$2
  if [ -z "$line" ] || [ "$line" = "NO-PLAN" ]; then
    fail "$label: EXPLAIN produced no plan"
    return 1
  fi
  case "$line" in
    *filesort*) fail "$label: filesort remains: $line"; return 1 ;;
  esac
  pass "$label: no filesort (plan: $line)"
  return 0
}

key_ok() { # key_ok <keyfield> -> 0 when key exists and is region,status-led
  local key=$1
  [ -n "$key" ] && [ "$key" != "NULL" ] || return 1
  local cols
  cols=$($MDB -N analytics -e "SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='analytics' AND TABLE_NAME='order_facts' GROUP BY INDEX_NAME HAVING INDEX_NAME='$key'" 2>/dev/null) || return 1
  case "$cols" in
    region,status*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 0) bring up the pristine seed
# ---------------------------------------------------------------------------
echo "== 0: reset database to pristine seed =="
if ! timeout 900 bash /opt/warehouse/dbctl.sh reset >/tmp/wf_reset.log 2>&1; then
  fail "dbctl reset failed (pristine seed not reachable)"
  tail -6 /tmp/wf_reset.log >&2
else
  pass "pristine seed up"
fi

# ---------------------------------------------------------------------------
# 1) sanity: the shipped schema must genuinely filesort on hidden query 1
# ---------------------------------------------------------------------------
sanity=$(explain_one "$H/case1/query.sql")
case "$sanity" in
  *filesort*) pass "sanity: pristine plan filesorts (brokenness confirmed)" ;;
  *) fail "sanity: pristine plan did not filesort: $sanity" ;;
esac

# ---------------------------------------------------------------------------
# 2) deliverables exist
# ---------------------------------------------------------------------------
for d in /app/migration.sql /app/explain_report.tsv; do
  if [ ! -s "$d" ]; then
    fail "missing or empty $d"
  else
    pass "deliverable present: $d"
  fi
done
if [ ! -s /app/migration.sql ] || [ ! -s /app/explain_report.tsv ]; then
  finalize
  exit 0
fi

# ---------------------------------------------------------------------------
# 3) apply the migration twice (idempotency)
# ---------------------------------------------------------------------------
echo "== 3: apply /app/migration.sql (twice) =="
if timeout 600 $MDB analytics < /app/migration.sql >/tmp/wf_mig1.log 2>&1; then
  pass "migration applied (pass 1)"
else
  fail "migration application failed (pass 1)"
  tail -6 /tmp/wf_mig1.log >&2
fi
if timeout 600 $MDB analytics < /app/migration.sql >/tmp/wf_mig2.log 2>&1; then
  pass "migration re-applied (pass 2: idempotent)"
else
  fail "migration re-application failed (not idempotent)"
  tail -6 /tmp/wf_mig2.log >&2
fi

# ---------------------------------------------------------------------------
# 4) hidden cases: plan + golden results
# ---------------------------------------------------------------------------
echo "== 4: hidden query cases =="
for c in case1 case2 case3; do
  qf="$H/$c/query.sql"
  line=$(explain_one "$qf")
  if plan_ok "$c/plan" "$line"; then
    key=$(printf '%s\n' "$line" | cut -f3)
    if key_ok "$key"; then
      pass "$c: expected key shape ($key)"
    else
      fail "$c: used key is not rollup-dimension-led (key='$key')"
    fi
  else
    key=$(printf '%s\n' "$line" | cut -f3)
    fail "$c: key check skipped/$( [ -n "$key" ] && echo "key='$key'" || echo 'no key' )"
  fi
  if run_q "$qf" "/tmp/wf_$c.tsv"; then
    if cmp -s "/tmp/wf_$c.tsv" "$H/$c/expected.tsv"; then
      pass "$c: results match golden ($(wc -l < "$H/$c/expected.tsv") lines)"
    else
      fail "$c: results differ from golden (got $(wc -l < "/tmp/wf_$c.tsv") lines, want $(wc -l < "$H/$c/expected.tsv"))"
      echo "--- first difference for $c:" >&2
      diff "/tmp/wf_$c.tsv" "$H/$c/expected.tsv" | head -5 >&2 || true
    fi
  else
    fail "$c: query could not be executed"
  fi
done

# ---------------------------------------------------------------------------
# 5) visible workload: plans, golden results, and the report comparison
# ---------------------------------------------------------------------------
echo "== 5: visible workload queries + explain_report.tsv =="
: > /tmp/wf_report.tsv
PAIRS="q1:q1_regional_status q2:q2_online_partition q3:q3_half_year q4:q4_three_dimensional"
for pair in $PAIRS; do
  n=${pair%%:*}
  f=${pair##*:}
  qf="/app/workload/$f.sql"
  line=$(explain_one "$qf")
  printf '%s\t%s\n' "$n" "$line" >> /tmp/wf_report.tsv
  if plan_ok "$n plan" "$line"; then
    key=$(printf '%s\n' "$line" | cut -f3)
    key_ok "$key" || fail "$n: used key is not rollup-dimension-led (key='$key')"
  fi
  if run_q "$qf" "/tmp/wf_$n.tsv"; then
    cmp -s "/tmp/wf_$n.tsv" "$H/workload_expected/$f.tsv" \
      && pass "$n: visible results match golden" \
      || fail "$n: visible results differ from golden"
  else
    fail "$n: query could not be executed"
  fi
done

if cmp -s /tmp/wf_report.tsv /app/explain_report.tsv; then
  pass "explain_report.tsv matches re-derived plans (4 lines)"
else
  fail "explain_report.tsv does not match re-derived plans"
  echo "--- expected report:" >&2
  cat /tmp/wf_report.tsv >&2 || true
  echo "--- agent report:" >&2
  cat /app/explain_report.tsv >&2 || true
fi
lines=$(wc -l < /app/explain_report.tsv 2>/dev/null || echo 0)
[ "$lines" = "4" ] || fail "explain_report.tsv must contain exactly 4 lines (has $lines)"

# ---------------------------------------------------------------------------
# 6) dependent view still resolves with identical content
# ---------------------------------------------------------------------------
echo "== 6: dependent view =="
views=$($MDB -N analytics -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='analytics' AND TABLE_NAME='vw_region_performance'" 2>/dev/null || echo 0)
if [ "${views:-0}" = "1" ]; then
  pass "view vw_region_performance exists"
else
  fail "view vw_region_performance missing (count=$views)"
fi
if timeout 120 $MDB --batch --raw analytics \
   -e "SELECT region, orders, revenue, avg_total FROM vw_region_performance ORDER BY region" \
   > /tmp/wf_view.tsv 2>/dev/null; then
  if cmp -s /tmp/wf_view.tsv "$H/view_expected.tsv"; then
    pass "view content matches golden"
  else
    fail "view content differs from golden"
    diff /tmp/wf_view.tsv "$H/view_expected.tsv" | head -5 >&2 || true
  fi
else
  fail "view could not be queried (does not resolve)"
fi

finalize
exit 0