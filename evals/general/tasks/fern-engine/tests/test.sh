#!/bin/bash
# foo verifier.: fern-engine. Executes the real deliverables /app/workflow.py
# and /app/artifact on visible fixtures and on hidden generalization cases,
# requires graceful non-zero exits on malformed inputs, and only then writes
# reward 1 to /logs/verifier/reward.txt.
set -u

REWARD=0
mkdir -p /logs/verifier
WF=/app/workflow.py
HID=/tests/hidden
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ok=1
fail(){ echo "FAIL: $*" >&2; ok=0; }

jq_cmp(){ # $1=got_file $2=python expr to evaluate on got
    python3 - "$1" "$2" <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
expr = sys.argv[2]
# expr is a small boolean expression that may reference `g` = got
g = got
if not eval(expr):
    print("mismatch", got, file=sys.stderr); sys.exit(1)
PY
}
[ -f "$WF" ] || fail "## /app/workflow.py missing"
[ -x "$WF" ] || fail "workflow.py not executable"
[ -d /app/artifact ] && [ -n "$(ls -A /app/artifact 2>/dev/null)" ] || fail "## /app/artifact missing/empty"

#### 1. visible: artifact loads/reloads and predicts deterministically, head=3 ####
o1="$WORK/pa.json"; o2="$WORK/pb.json"
if python3 $WF predict /app/artifact /app/data/eval.csv > "$o1" 2>/dev/null \
   && python3 $WF predict /app/artifact /app/data/eval.csv > "$o2" 2>/dev/null; then
    jq_cmp "$o1" 'got["num_labels"]==3 and len(got["predictions"])==3 \
                  and all(0<=p<3 for p in got["predictions"])' || fail "artifact predict range/dim"
    python3 - "$o1" "$o2" <<'PY' || fail "artifact reload not deterministic"
import json,sys
a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2]))
assert a==b, (a,b)
PY
else
    fail "artifact predict command failed"
fi

# 2. visible train+reload confirm (fresh artifact dir)
if python3 "$WF" train /app/data/train.csv "$WORK/art2" > "$o1" 2>/dev/null; then
    jq_cmp "$o1" 'got["reload_ok"] is True and got["num_labels"]==3' || fail "train visible reload flag"
else
    fail "train visible failed"
fi

# 3. visible rebuild from /app/state_seed.pkl -> expect dims (5,6,3)
if python3 "$WF" rebuild /app/state_seed.pkl "$WORK/rb1" > "$o1" 2>/dev/null; then
    jq_cmp "$o1" 'got["loaded"]==True and got=={"in_features":5,"hidden_size":6,"num_labels":3,"loaded":True}'
else
    fail "rebuild visible failed"
fi

# 4. visible reconfigure base_clf -> K=5
if python3 "$WF" reconfigure /app/base_clf "$WORK/rc1" 5 > "$o1" 2>/dev/null; then
    jq_cmp "$o1" 'got["num_labels"]==5' || fail "reconfigure visible dim"
    if python3 "$WF" predict "$WORK/rc1" "/app/base_eval.csv" > "$o2" 2>/dev/null; then
        jq_cmp "$o2" 'got["num_labels"]==5 and all(0<=p<5 for p in got["predictions"])'
    else
        fail "predict on reconfigured model failed"
    fi
else
    fail "reconfigure visible failed"
fi

# 5. visible cache+offline (offline strictly via local_files_only)
cp -r /app/pretrained_lm "$WORK/lmc"
if python3 "$WF" cache "$WORK/lmc" "$WORK/cache" > "$o1" 2>/dev/null \
   && [ -f "$WORK/cache/config.json" ] \
   && [ -f "$WORK/cache/state.pt" -o -f "$WORK/cache/model.safetensors" -o -f "$WORK/cache/pytorch_model.bin" ] \
   && [ -f "$WORK/cache/tokenizer.json" -o -f "$WORK/cache/vocab.txt" ]; then
    jq_cmp "$o1" 'got["cached"].endswith("/cache")'
    rm -rf "$WORK/lmcopy"
    if HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 "$WF" offline "$WORK/cache" "fern grotto" > "$o1" 2>/dev/null \
       && HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 "$WF" offline "$WORK/cache" "fern grotto" > "$o2" 2>/dev/null; then
        jq_cmp "$o1" 'got["new_tokens"]==4'
        python3 - "$o1" "$o2" <<'PY' || fail "offline not deterministic"
import json,sys
assert json.load(open(sys.argv[1]))==json.load(open(sys.argv[2]))
PY
    else
        fail "offline (local-only) generation failed"
    fi
else
    fail "cache visible failed or cache incomplete"
fi

# ============================== HIDDEN CASES ==============================
# hidden offline (second model)
if [ -d "$HID/h_offline/model" ]; then
    python3 "$WF" cache "$HID/h_offline/model" "$WORK/hc" >/dev/null 2>&1 \
        || fail "hidden offline cache failed"
    PR=$(cat "$HID/h_offline/prompt.txt")
    if HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 "$WF" offline "$WORK/hc" "$PR" >"$o1" 2>/dev/null; then
        jq_cmp "$o1" 'got["new_tokens"]==4'
    else
        fail "hidden offline generation failed"
    fi
fi

# hidden rebuild) second state dict with a different shape
if [ -f "$HID/h_rebuild/state.pkl" ]; then
    python3 "$WF" rebuild "$HID/h_rebuild/state.pkl" "$WORK/hrb" >"$o1" 2>/dev/null \
        || fail "hidden rebuild failed"
    jq_cmp "$o1" 'got["in_features"]==4 and got["hidden_size"]==5 and got["num_labels"]==2' \
        || fail "hidden rebuild dims"
fi

# hidden reconfigure) retarget a fresh base to K=7
if [ -d "$HID/h_reconfig/base" ] && [ -f "$HID/h_reconfig/K.txt" ]; then
    K=$(cat "$HID/h_reconfig/K.txt")
    python3 "$WF" reconfigure "$HID/h_reconfig/base" "$WORK/hrc" "$K" >"$o1" 2>/dev/null \
        || fail "hidden reconfigure failed"
    jq_cmp "$o1" 'got["num_labels"]==7' || fail "hidden reconfigure dim"
    python3 "$WF" predict "$WORK/hrc" "$HID/h_reconfig/eval.csv" >"$o2" 2>/dev/null \
        || fail "predict hidden reconfigure"
    jq_cmp "$o2" 'got["num_labels"]==7 and all(0<=p<7 for p in got["predictions"])' \
        || fail "hidden reconfigure predict"
fi

# hidden train) hidden data; artifact must reload+agree with itself
if [ -f "$HID/h_train/data/train.csv" ]; then
    python3 "$WF" train "$HID/h_train/data/train.csv" "$WORK/hart" >"$o1" 2>/dev/null \
        || fail "hidden train failed"
    jq_cmp "$o1" 'got["reload_ok"] is True and got["num_labels"]==3'
    python3 "$WF" predict "$WORK/hart" "$HID/h_train/data/eval.csv" >"$o1" 2>/dev/null \
        && python3 "$WF" predict "$WORK/hart" "$HID/h_train/data/eval.csv" >"$o2" 2>/dev/null \
        || fail "hidden predict failed"
    python3 - "$o1" "$o2" <<'PY' || fail "hidden train reload not deterministic"
import json,sys
a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2]))
assert a==b and all(0<=p<=2 for p in a["predictions"]), (a,b)
PY
fi

# --------------------------- malformed inputs must fail ---------------------------
expect_err(){ # $1 = full command prefix (func), $2 description
    if bash -c "set -o pipefail; $1 >/dev/null 2>&1"; then
        fail "malformed '$2' unexpectedly succeeded"; return 1
    fi
    return 0
}
expect_err "python3 $WF rebuild $HID/errors/e1_rebuild_bad/thing.bin $WORK/e" "rebuild-bad-state"
expect_err "python3 $WF train $HID/errors/e2_train_empty/train.csv $WORK/e" "train-empty"
expect_err "python3 $WF offline $WORK/no_such_cache_dir probe" "offline-missing-cache"
expect_err "python3 $WF reconfigure /app/base_clf $WORK/e 0" "reconfigure-zero"
expect_err "python3 $WF predict /app/nope/nope.csv $WORK/e" "predict-missing-input"

if [ "$ok" = 1 ]; then REWARD=1; fi
echo "$REWARD" > /logs/verifier/reward.txt
exit 0