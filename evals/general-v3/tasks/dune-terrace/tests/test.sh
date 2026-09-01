#!/bin/bash
# dune-terrace verifier (executes-deliverable).
# Recompiles the agent's /app/ptrace.c, re-runs it to regenerate the color and
# depth rasters, checks them against the stored reference within tolerance,
# verifies the compressed source-size budget, and re-runs the PNG icon
# generator to confirm /app/out.png is a real, deterministic render.
set -u
ok=1
fail(){ echo "FAIL: $*"; ok=0; }

mkdir -p /logs/verifier
GOLD=/tests/golden
CHECK=/tests/imgcheck.py

for f in /app/ptrace.c /app/make_icon.py /app/scene_color.pfm \
         /app/scene_depth.pgm /app/out.png; do
    [ -f "$f" ] || fail "missing deliverable $f"
done
for f in /tests/imgcheck.py /tests/golden/target.ppm \
         /tests/golden/scene_color.pfm /tests/golden/scene_depth.pgm \
         /tests/golden/out.png; do
    [ -f "$f" ] || fail "missing verifier asset $f"
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- 1) compressed source-size budget for the C path tracer ---
SZ=$(gzip -c /app/ptrace.c | wc -c)
echo "ptrace.c compressed bytes: $SZ"
if [ "$SZ" -le 5000 ]; then
    echo "source-sizebudget OK"
else
    fail "ptrace.c compressed size $SZ exceeds 5000-byte budget"
fi

# --- 2) rebuild ptrace.c and re-render from the scene data ---
if ! cc -O2 -o "$WORK/ptrace" /app/ptrace.c -lm 2>"$WORK/cc.err"; then
    fail "ptrace.c did not compile: $(tail -1 "$WORK/cc.err")"
else
    echo "compile OK"
    if ! "$WORK/ptrace" /app/scene.json "$WORK/target.ppm" \
            "$WORK/scene_color.pfm" "$WORK/scene_depth.pgm" 2>"$WORK/run.err"; then
        fail "ptrace run failed: $(tail -1 "$WORK/run.err")"
    fi
fi

if [ -f "$WORK/target.ppm" ]; then
    python3 "$CHECK" target "$WORK/target.ppm" "$GOLD/target.ppm" 0.94 \
        || fail "color reconstruction (target.ppm) below SSIM"
fi
if [ -f "$WORK/scene_color.pfm" ]; then
    python3 "$CHECK" color "$WORK/scene_color.pfm" "$GOLD/scene_color.pfm" 0.94 \
        || fail "scene_color.pfm below SSIM"
fi
if [ -f "$WORK/scene_depth.pgm" ]; then
    python3 "$CHECK" depth "$WORK/scene_depth.pgm" "$GOLD/scene_depth.pgm" 0.94 5 0.95 \
        || fail "scene_depth.pgm below similarity/density"
fi

# --- 3) PNG icon generator: valid 64x64 scene structurally, and deterministic ---
if ! python3 /app/make_icon.py "$WORK/icon.png" 2>"$WORK/icon.err"; then
    fail "make_icon.py failed: $(tail -1 "$WORK/icon.err")"
else
    python3 "$CHECK" icon "$WORK/icon.png" 64 64 \
        || fail "icon is not a valid 64x64 RGB PNG of the described scene"
    # determinism: a second run must be byte-identical (no timestamps/RNG/zlib drift)
    if ! python3 /app/make_icon.py "$WORK/icon2.png" 2>"$WORK/icon.err"; then
        fail "make_icon.py second run failed: $(tail -1 "$WORK/icon.err")"
    else
        python3 "$CHECK" iconsame "$WORK/icon.png" "$WORK/icon2.png" \
            || fail "make_icon.py is not deterministic across runs"
    fi
fi

# --- 4) hidden scenes built from /app/ptrace.c must render at the right size ---
for d in /tests/hidden/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    scene="$d/scene.json"
    [ -f "$scene" ] || { fail "hidden $name missing scene.json"; continue; }
    exp=$(python3 - "$scene" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
print('%d %d' % (j.get('width', 160), j.get('height', 100)))
PY
    )
    eww=${exp% *}
    ehh=${exp#* }
    if "$WORK/ptrace" "$scene" \
            "$WORK/${name}_t.ppm" "$WORK/${name}_c.pfm" "$WORK/${name}_d.pgm" \
            2>"$WORK/h.err"; then
        python3 "$CHECK" dims "$WORK/${name}_t.ppm" "$WORK/${name}_c.pfm" \
            "$WORK/${name}_d.pgm" "$eww" "$ehh" \
            || fail "hidden $name output size mismatch"
    else
        fail "ptrace failed on hidden $name: $(tail -1 "$WORK/h.err")"
    fi
done

[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"