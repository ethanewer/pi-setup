#!/bin/bash
# Verifier for rose-frame (executes-deliverable).
# Executes /app/render.py on the visible scene and on every hidden scene under
# /tests/hidden, comparing each produced PPM against the expected reference.
reward=0
mkdir -p /logs/verifier
ok=1

fail() { echo "FAIL: $*"; ok=0; }

if [ ! -x /app/render.py ] && [ ! -f /app/render.py ]; then
    fail "missing deliverable /app/render.py"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if command -v python3 >/dev/null; then
    run_render() { python3 /app/render.py "$1" "$2"; }
else
    run_render() { /app/render.py "$1" "$2"; }
fi

# Visible case.
out="$WORK/visible.ppm"
if ! run_render /app/scene.json "$out" 2>"$WORK/err.txt"; then
    fail "render.py failed on visible scene: $(cat "$WORK/err.txt")"
elif [ ! -f "$out" ]; then
    fail "no output produced for visible scene"
elif cmp -s "$out" /tests/expected.ppm; then
    echo "visible OK"
else
    fail "visible output mismatch"
fi

# Hidden cases.
n=0
for d in /tests/hidden/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    scene="$d/scene.json"
    expect="$d/expected.ppm"
    [ -f "$scene" ] || { fail "hidden case $name missing scene.json"; continue; }
    [ -f "$expect" ] || { fail "hidden case $name missing expected.ppm"; continue; }
    out="$WORK/$name.ppm"
    if ! run_render "$scene" "$out" 2>"$WORK/$name.err"; then
        fail "render.py crashed on hidden case $name"; cat "$WORK/$name.err"
    elif [ ! -f "$out" ]; then
        fail "no output produced for hidden case $name"
    elif cmp -s "$out" "$expect"; then
        n=$((n+1)); echo "hidden $name OK"
    else
        fail "hidden case $name output mismatch"
    fi
done

[ "$ok" -eq 1 ] && [ -n "$(find /tests/hidden -mindepth 1 -maxdepth 1 -type d)" ] && {
    echo "all checks passed (visible + $n hidden)"
    reward=1
}

echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"