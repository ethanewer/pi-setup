#!/bin/bash
# Verifier for night-console (executes-deliverable).
# Rewards 1 only if /app/session.py runs correctly on the visible case AND on
# every hidden case in /tests/hidden/.
mkdir -p /logs/verifier
reward=1

DELIVERABLE=/app/session.py

if [ ! -f "$DELIVERABLE" ]; then
    echo "missing deliverable: $DELIVERABLE"
    reward=0
else
    check_case() {
        local prog="$1" inputf="$2" wantf="$3"
        local got
        got="$(python3 "$prog" < "$inputf" 2>/tmp/verr)" \
            || { echo "runtime failure on $inputf"; reward=0; return; }
        local errcode
        errcode=0
        python3 - "$wantf" "$got" <<'PY' || errcode=1
import json, sys
wantf, got = sys.argv[1], sys.argv[2]
got_lines = got.split("\n")
if got_lines and got_lines[-1] == "":
    got_lines.pop()
with open(wantf) as f:
    content = f.read().strip()
if wantf.endswith(".json"):
    want = json.loads(content)
    if not isinstance(want, list):
        want = list(want)
else:
    want = content.splitlines()
if got_lines != want:
    sys.stderr.write("MISMATCH %s\n  got : %r\n  want: %r\n"
                     % (wantf, got_lines, want))
    sys.exit(1)
PY
        if [ "$errcode" -ne 0 ]; then
            reward=0
        else
            echo "PASS $(basename "$inputf")"
        fi
    }

    check_case "$DELIVERABLE" /tests/visible_input.txt /tests/expected.json
    for in in /tests/hidden/*.in; do
        [ -e "$in" ] || continue
        exp="${in%.in}.exp"
        check_case "$DELIVERABLE" "$in" "$exp"
    done
fi

echo "$reward" > /logs/verifier/reward.txt
