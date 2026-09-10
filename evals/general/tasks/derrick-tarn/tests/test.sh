#!/bin/bash
# Verifier for derrick-tarn (gallery-dl picdrome extractor task).
#
# Checks, in order:
#   1. the deliverable /app/src/gallery_dl/extractor/picdrome.py exists,
#   2. the unmodified gallery-dl CLI (run from /app/src) discovers the
#      picdrome extractor via its own --list-extractors mechanism,
#   3. for each hidden case c1..c3: the verifier starts its own mock-server
#      instance on the loopback port 8899 serving /tests/hidden/<case>/site,
#      then runs the gallery-dl CLI against the hidden gallery and asserts
#      download bytes, exact file naming and exact -j metadata via
#      /tests/check_case.py.
# Reward is binary and written on every exit path.
set -u
mkdir -p /logs/verifier

reward=0
failures=0
PORT=8899
SRVPID=""

cleanup() {
    if [ -n "$SRVPID" ]; then kill "$SRVPID" 2>/dev/null; wait "$SRVPID" 2>/dev/null; fi
}

on_exit() {
    cleanup
    if [ ! -f /logs/verifier/reward.txt ]; then
        echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2
        mkdir -p /logs/verifier
        echo 0 > /logs/verifier/reward.txt
    fi
}
trap on_exit EXIT

wait_for_server() {
    local url="$1"
    local i
    for i in $(seq 1 40); do
        if curl -sf -o /dev/null "$url"; then return 0; fi
        sleep 0.25
    done
    return 1
}

# ---- 1. deliverable exists ---------------------------------------------
if [ ! -f /app/src/gallery_dl/extractor/picdrome.py ]; then
    echo "FAIL: deliverable /app/src/gallery_dl/extractor/picdrome.py is missing (agent never wrote the extractor module)" >&2
    failures=1
else
    echo "deliverable: present"
fi

# ---- 2. /app/src is the real pinned clone -------------------------------
if [ ! -f /app/src/gallery_dl/extractor/common.py ] || [ ! -f /app/src/pyproject.toml ]; then
    echo "FAIL: /app/src is not the gallery-dl source tree" >&2
    failures=1
fi

# ---- 3. gallery-dl's own discovery lists the picdrome extractor ----------
REG_LOG=$(mktemp)
if (cd /app/src && python3 -m gallery_dl --list-extractors picdrome >"$REG_LOG" 2>&1) \
        && grep -qi "Picdrome" "$REG_LOG"; then
    echo "discovery: --list-extractors picdrome lists the extractor"
    rm -f "$REG_LOG"
else
    echo "FAIL: gallery-dl --list-extractors picdrome does not list a picdrome extractor (offending output:)" >&2
    sed 's/^/    /' "$REG_LOG" >&2
    rm -f "$REG_LOG"
    failures=1
fi

# ---- 4. hidden cases ------------------------------------------------------
mkdir -p /tmp/gdhome
for CASE in /tests/hidden/c1 /tests/hidden/c2 /tests/hidden/c3; do
    [ -d "$CASE" ] || { echo "FAIL: missing hidden case dir $CASE" >&2; failures=1; continue; }

    SLUG=$(python3 -c "import json,sys; print(json.load(open('$CASE/expected.json'))['slug'])")

    python3 /app/mock_site/server.py --root "$CASE/site" --port "$PORT" &
    SRVPID=$!
    BASE="http://127.0.0.1:$PORT/gallery/$SLUG/"

    ok=1
    if ! wait_for_server "$BASE"; then
        echo "FAIL $CASE: mock server did not come up on port $PORT" >&2
        ok=0
    else
        WORK=$(mktemp -d)
        OUT="$WORK/dl"
        mkdir -p "$OUT"
        (cd /app/src && HOME=/tmp/gdhome python3 -m gallery_dl -d "$OUT" "$BASE" \
            >"$WORK/dl.log" 2>&1)
        (cd /app/src && HOME=/tmp/gdhome python3 -m gallery_dl -j "$BASE" \
            >"$WORK/meta.json" 2>"$WORK/meta.err")

        if python3 /tests/check_case.py "$CASE" "$OUT" "$WORK/meta.json"; then
            echo "$CASE: download+naming+bytes+metadata OK"
        else
            ok=0
        fi
        rm -rf "$WORK"
    fi

    if [ $ok -ne 1 ]; then
        echo "FAIL $CASE: hidden picdrome gallery verification failed" >&2
        failures=1
    fi

    cleanup
    SRVPID=""
done

# ---- 5. reward -------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFICATION FAILED ($failures failing area(s)); scoring 0"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0