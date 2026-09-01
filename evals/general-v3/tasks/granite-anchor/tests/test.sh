#!/bin/bash
# Verifier for tasks/granite-anchor (executes-deliverable).
# Re-runs the agent's /app/search.py on the primary config and on every hidden
# config, validating all artifact formats against an independent reference BFS
# backend (tests/refcheck.py). Writes numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

FAIL=false
failadd(){ echo "FAIL: $1"; FAIL=true; }

REF=/tests/refcheck.py
H=/tests/hidden

# ---------------------------------------------------------------------------
# 0) deliverable must exist before anything else
# ---------------------------------------------------------------------------
if [ ! -f /app/search.py ]; then
    echo "0" > /logs/verifier/reward.txt
    echo "FAIL: /app/search.py missing"
    echo "REWARD=0"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1) primary scenario already emitted to /app (oracle ran search.py there),
#    and we re-run it fresh into a scratch dir to prove re-runability.
# ---------------------------------------------------------------------------
rm -rf /tmp/p_primary
python3 /app/search.py /app/config.json /tmp/p_primary >/tmp/rp.out 2>&1 || failadd "search.py failed on primary config"
if ! python3 "$REF" /app/config.json /tmp/p_primary >/tmp/rc_primary.log 2>&1; then
    failadd "primary re-run artifacts mismatch; $(tail -1 /tmp/rc_primary.log)"
fi
# the deliverables that were placed at /app by solve.sh must also be correct
if ! python3 "$REF" /app/config.json /app >/tmp/rc_app.log 2>&1; then
    failadd "/app artifacts mismatch; $(tail -1 /tmp/rc_app.log)"
else
    for need in /app/search.py /app/frontier.sha256 /app/depth_summary.txt \
                /app/move_trace.json /app/dag_edges.csv; do
        [ -e "$need" ] || failadd "missing /app deliverable $need"
    done
    ls /app/frontier_*.txt >/dev/null 2>&1 || failadd "no /app/frontier_*.txt files"
fi

# ---------------------------------------------------------------------------
# 2) hidden cases: re-run the deliverable on each hidden config and compare
# ---------------------------------------------------------------------------
any_hidden=false
for c in "$H"/*.json; do
    [ -e "$c" ] || continue
    name=$(basename "$c" .json)
    any_hidden=true
    out=/tmp/hout_$name
    rm -rf "$out"
    mkdir -p "$out"
    python3 /app/search.py "$c" "$out" >/tmp/hruns_$name.log 2>&1 \
        || { failadd "search.py failed on hidden $name"; continue; }
    if ! python3 "$REF" "$c" "$out" >/tmp/hcheck_$name.log 2>&1; then
        failadd "hidden $name mismatch; $(tail -1 /tmp/hcheck_$name.log)"
    fi
done
if [ "$any_hidden" = false ]; then
    failadd "no hidden cases present"
fi

# ---------------------------------------------------------------------------
# Finish
# ---------------------------------------------------------------------------
if [ "$FAIL" = true ]; then
    echo "0" > /logs/verifier/reward.txt
else
    echo "1" > /logs/verifier/reward.txt
fi
echo "REWARD=$(cat /logs/verifier/reward.txt)"
exit 0