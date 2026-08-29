#!/usr/bin/env bash
# Oracle: build the whole deliverable set by doing the work, then produce the
# result files by RUNNING the work. Never reads /tests.
set -euo pipefail

# 1) Write the authored programs into /app.
cp /solution/service.py /app/service.py
cp /solution/mgmt-request.sh /app/mgmt-request.sh
cp /solution/reserve.py /app/reserve.py
cp /solution/solve.py /app/solve.py
cp /solution/value.py /app/value.py
chmod +x /app/mgmt-request.sh /app/reserve.py /app/solve.py /app/service.py

# 2) Place the required reservation through the live API: this RUNS the
#    service and reserve.py and produces /app/reservations.json.
python3 /app/service.py >/tmp/oracle-service.log 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 2
python3 /app/reserve.py --venue "Woodbank Pavilion" --company "Keystone Freight"
test -f /app/reservations.json || { echo "reserve.py did not write /app/reservations.json" >&2; exit 1; }
kill $SRV 2>/dev/null || true
wait $SRV 2>/dev/null || true
trap - EXIT

# 3) Compute and persist the objective's integer part (RUNNING solve.py).
#    solve.py writes /app/answer.txt with exactly the floored integer.
python3 /app/solve.py
test -f /app/answer.txt || { echo "solve.py did not write /app/answer.txt" >&2; exit 1; }

# 4) Run the value-object self-check, capturing the log deliverable.
python3 /app/value.py > /app/value-test.log 2>&1

echo "oracle finished"