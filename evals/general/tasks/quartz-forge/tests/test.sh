#!/bin/bash
#
# quartz-forge verifier. Runs the agent's left-behind generator (/app/forge_report.py)
# against the visible config and every hidden config in /tests/hidden, and compares
# each of the five produced artifacts byte-for-byte against the independent reference
# computation (tests/ref.py). Reward is 1 only when every case and every artifact
# matches.
set -u

mkdir -p /logs/verifier

PY=$(command -v python3 || echo /usr/bin/python3)
REF=/tests/ref.py
# One explicit /app/... path per deliverable artifact (matches task.toml metadata.deliverables).
# Each artifact is produced by /app/forge_report.py and byte-compared against ref.py below.
ARTIFACTS="/app/report.txt /app/decision.txt /app/result.txt /app/construct.txt /app/out.jpg"
TMPDIR=$(mktemp -d)
GEN=/app/forge_report.py

overall=1
msgs=""

check_one() {
    local cfg="$1"
    local tag="$2"
    local ok=1
    local sub=""

    # Generate expected ground truth for this config.
    if ! "$PY" "$REF" "$cfg" "$TMPDIR/exp_$tag" 2>"$TMPDIR/ref_err_$tag"; then
        echo 0 > /logs/verifier/reward.txt
        exit 1
    fi

    # Run the agent's generator on this config.
    if ! "$PY" "$GEN" "$cfg" >"$TMPDIR/gen_out_$tag" 2>"$TMPDIR/gen_err_$tag"; then
        overall=0
        msgs="$msgs ${tag}:generator-failed"
        return
    fi

    for art in $ARTIFACTS; do
        name=${art#/app/}
        if [ ! -f "$art" ]; then
            ok=0
            sub="$sub $art:missing"
            continue
        fi
        if ! cmp -s "$art" "$TMPDIR/exp_$tag/$name"; then
            ok=0
            sub="$sub $art:mismatch"
        fi
    done

    if [ "$ok" != "1" ]; then
        overall=0
        msgs="$msgs ${tag}:[$sub]"
    fi
}

# ---- Visible case: run the generator on the default config (no argv) ----
if ! "$PY" "$GEN" >"$TMPDIR/gen_out_vis" 2>"$TMPDIR/gen_err_vis"; then
    overall=0
    msgs="$msgs visible:generator-failed"
else
    if ! "$PY" "$REF" /app/data/config.json "$TMPDIR/exp_vis" 2>/dev/null; then
        echo 0 > /logs/verifier/reward.txt
        exit 1
    fi
    for art in $ARTIFACTS; do
        name=${art#/app/}
        if [ ! -f "$art" ]; then
            overall=0
            msgs="$msgs visible:${art}:missing"
        elif ! cmp -s "$art" "$TMPDIR/exp_vis/$name"; then
            overall=0
            msgs="$msgs visible:${art}:mismatch"
        fi
    done
fi

# ---- Hidden cases ----
shopt -s nullglob
idx=0
for h in /tests/hidden/*.json; do
    idx=$((idx+1))
    check_one "$h" "h$idx"
done
if [ "$idx" -eq 0 ]; then
    echo 0 > /logs/verifier/reward.txt
    exit 1
fi

# Regenerate the visible deliverables last so /app reflects the default config.
"$PY" "$GEN" >/dev/null 2>&1 || true

if [ "$overall" = "1" ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo "FAILED:$msgs" >> "$TMPDIR/notes" 2>/dev/null
    echo 0 > /logs/verifier/reward.txt
fi
exit 0
