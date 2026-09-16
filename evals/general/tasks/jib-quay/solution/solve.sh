#!/bin/bash
#
# jib-quay oracle.  From a pristine container this:
#   1. installs the repaired service at /app/service.py;
#   2. authors the root-cause writeup /app/diagnosis.md;
#   3. smoke-tests the repair with the shipped driver: the documented
#      concurrent mix must complete (the shipped service deadlocks on it).
# Never reads /tests and never hardcodes the hidden fixtures.
set -euo pipefail

cp /solution/service_fixed.py /app/service.py
cp /solution/diagnosis.md /app/diagnosis.md
chmod 0644 /app/service.py /app/diagnosis.md

# Smoke test: the documented concurrent mix must now COMPLETE.  The shipped
# service stalls on it (deadlock); the repaired one finishes in well under a
# second, so this is a genuine check that the deliverable is the fixed build.
if ! python3 /app/driver.py \
        --service /app/service.py \
        --ledger /app/ledger.json \
        --mix /app/mix_visible.json \
        --port 28911 \
        --latency 0.02 \
        --out /tmp/jq_oracle_smoke.json 2>/tmp/jq_oracle_smoke.err; then
  echo "oracle smoke: concurrent mix did not complete against the fix" >&2
  cat /tmp/jq_oracle_smoke.err >&2 || true
  exit 1
fi

python3 - <<'PY'
import json
r = json.load(open("/tmp/jq_oracle_smoke.json"))
if not r.get("ok") or not r.get("journal") or len(r["journal"]) != 12:
    print("oracle smoke: unexpected report %r" % r, file=__import__("sys").stderr)
    raise SystemExit(1)
print("oracle smoke OK: %d transfers, %.3fs, no stall" %
      (len(r["journal"]), r.get("elapsed", -1)))
PY

echo "solve.sh done: /app/service.py (repaired) + /app/diagnosis.md"