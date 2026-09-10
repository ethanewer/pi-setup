#!/bin/bash
#
# Oracle for tasks/wale-ferry. Brings the live MariaDB up, verifies the
# filesort symptom on the visible workload, writes the idempotent schema
# migration, applies it twice, re-derives the EXPLAIN rows for the four
# workload queries, and writes the two deliverables.
set -u

SOCK=/run/mysqld/mysqld.sock
MDB="mariadb --socket=$SOCK"

echo "== [1] bring the scenario up (seeds the pristine database) =="
/opt/warehouse/dbctl.sh up || { echo "oracle: dbctl up failed" >&2; exit 1; }

echo "== [2] diagnose: confirm the filesort symptom on the pristine workload =="
: > /tmp/wf_before.tsv
$MDB --batch --raw analytics < /app/workload/q1_regional_status.sql > /tmp/wf_before.tsv \
  || { echo "oracle: could not run q1" >&2; exit 1; }

PAIRS="q1:q1_regional_status q2:q2_online_partition q3:q3_half_year q4:q4_three_dimensional"
for pair in $PAIRS; do
  n=${pair%%:*}
  f=${pair##*:}
  plan=$($MDB --batch --column-names=0 analytics -e "EXPLAIN $(cat /app/workload/$f.sql)" 2>/dev/null || true)
  echo "$n BEFORE: $plan"
  case " $plan " in
    *filesort*) ;;
    *) echo "oracle: plan for $n does not filesort on pristine data: $plan" >&2; exit 1 ;;
  esac
done

echo "== [3] write the idempotent migration =="
cat > /app/migration.sql <<'SQL'
-- wale-ferry schema fix: restore an optimal access path for the regional
-- rollup workload on analytics.order_facts.
--
-- Diagnosis (confirmed live with EXPLAIN against the pristine seed): the only
-- secondary indexes on order_facts are transaction-shaped (a customer_id FK
-- index and a status-filter index). Every analytical rollup in the workload
-- therefore plans a full table scan plus "Using temporary; Using filesort".
--
-- Fix: a covering composite key whose leading columns match the grouping and
-- sort order the reports aggregate by. CREATE OR REPLACE INDEX keeps the
-- script idempotent, so re-applying it is a no-op.
CREATE OR REPLACE INDEX idx_order_facts_analytics
  ON analytics.order_facts (region, status, channel, placed_at, total);
SQL

echo "== [4] apply it twice (idempotency proof) =="
$MDB analytics < /app/migration.sql || { echo "oracle: migration application failed" >&2; exit 1; }
$MDB analytics < /app/migration.sql || { echo "oracle: migration is not idempotent" >&2; exit 1; }

echo "== [5] re-derive the plans and write explain_report.tsv =="
: > /app/explain_report.tsv
for pair in $PAIRS; do
  n=${pair%%:*}
  f=${pair##*:}
  line=$($MDB --batch --column-names=0 analytics -e "EXPLAIN $(cat /app/workload/$f.sql)" 2>/dev/null \
    | awk -F '\t' '{print $2"\t"$4"\t"$6"\t"$10}' | head -1 || true)
  case " $line " in
    *filesort*) echo "oracle: filesort remains after fix ($n): $line" >&2; exit 1 ;;
  esac
  printf '%s\t%s\n' "$n" "$line" >> /app/explain_report.tsv
  echo "$n AFTER: $line"
done

echo "== [6] sanity: results and dependent view unchanged =="
$MDB --batch --raw analytics < /app/workload/q1_regional_status.sql > /tmp/wf_after.tsv \
  || { echo "oracle: could not run q1 after fix" >&2; exit 1; }
if ! cmp -s /tmp/wf_before.tsv /tmp/wf_after.tsv; then
  echo "oracle: q1 results changed after the migration" >&2
  exit 1
fi
n=$($MDB -N analytics -e "SELECT COUNT(*) FROM vw_region_performance" 2>/dev/null || echo 0)
[ "${n:-0}" -ge 1 ] || { echo "oracle: dependent view broken or empty" >&2; exit 1; }

echo "oracle complete: view rows=$n, report lines=$(wc -l < /app/explain_report.tsv)"
exit 0