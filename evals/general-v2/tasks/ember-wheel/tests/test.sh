#!/bin/bash
# Verifier for the ember-wheel task.
#
# The deliverable is a repaired native extension (/app/native.c) whose module
# `snapvec` must fold EVERY element of an integer vector into a deterministic
# 8-hex checksum. The harness /app/runner.py is data-driven: it reads vectors
# from an input JSON and reports per-vector checksums, so wrong output can only
# come from an unrepaired or buggy extension.
#
# This verifier rebuilds the extension from the delivered /app/native.c (so a
# prebuilt .so or a pure-Python shortcut cannot mask a wrong source), then runs
# the deliverable on /app/bench.json (visible) and on hidden inputs under
# /tests/hidden, and checks structural equality of the reports.
#
# Always writes a numeric reward to /logs/verifier/reward.txt.
mkdir -p /logs/verifier
reward=0
ok=1

cd /app
report=/tmp/verifier_report.json

# The deliverables are /app/native.c (repaired C source), /app/setup.py
# (packaging), and /app/runner.py (data-driven harness).
for d in /app/native.c /app/setup.py /app/runner.py; do
    if [ ! -f "$d" ]; then
        echo "missing deliverable $d" >&2
        ok=0
    fi
done

# The harness must actually invoke the native module on the input data (a
# hardcoded table would not be a reusable deliverable).
if ! grep -q 'snapvec.checksum' /app/runner.py; then
    echo '/app/runner.py does not invoke snapvec.checksum on the input data' >&2
    ok=0
fi

# 1) Rebuild the extension from the real delivered C source.
if ! python3 /app/setup.py build_ext --inplace > /tmp/build.log 2>&1; then
    echo "snapvec rebuild from delivered native.c failed (see /tmp/build.log)" >&2
    ok=0
else
    # confirm the module is importable
    if ! python3 -c 'import snapvec' >/tmp/imp.log 2>&1; then
        echo "snapvec built but not importable (see /tmp/imp.log)" >&2
        ok=0
    fi
fi

# check INPUT EXPECTED : run the harness and require exact JSON equality.
check() {
    local inp="$1" exp="$2"
    rm -f "$report"
    if ! python3 runner.py --input "$inp" --output "$report" >/tmp/run.log 2>&1; then
        echo "runner failed on $(basename "$inp") (see /tmp/run.log)" >&2
        return 1
    fi
    python3 - "$report" "$exp" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
sys.exit(0 if got == want else 1)
PY
}

if [ "$ok" = 1 ]; then
    # 2) Visible case.
    if ! check /app/bench.json /tests/expected.json; then
        echo "visible case (bench.json) produced the wrong report" >&2
        ok=0
    fi

    # 3) Hidden cases.
    cnt=0
    for pin in /tests/hidden/*.in.json; do
        [ -e "$pin" ] || continue
        cnt=$((cnt + 1))
        exp="${pin%.in.json}.out.json"
        if ! check "$pin" "$exp"; then
            echo "hidden case produced the wrong report: $pin" >&2
            ok=0
        fi
    done
    [ "$cnt" -ge 1 ] || ok=0
fi

[ "$ok" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"