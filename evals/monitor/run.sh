#!/usr/bin/env bash
# Launch all 7 benchmark tasks in parallel against one harness setup.
#
# HARNESS selects the agent under test, always resolved from the LIVE setup
# (nothing here pins a version):
#   pi   installed pi CLI, --mode rpc, isolated agent dir whose only package
#        is the monitor fork symlinked from the setup's installed copy
#   p    installed p wrapper (lean profile; it owns its agent dir, so the
#        monitor extension is absent by design)
#   occ  installed occ wrapper (Claude Code on pinned open-weight models)
#   ocdx installed ocdx wrapper (Codex CLI on pinned open-weight models)
#
# MODEL is the pi-style provider/model for pi/p (default
# openrouter/z-ai/glm-5.3-flash); occ/ocdx receive the bare OpenRouter slug,
# which their wrappers accept directly.
set -uo pipefail
cd "$(dirname "$0")"
HARNESS="${HARNESS:-pi}"
case "$HARNESS" in pi|p|occ|ocdx) ;; *) echo "HARNESS must be pi, p, occ, or ocdx (got: $HARNESS)" >&2; exit 2 ;; esac
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
SEED="${SEED:-$RANDOM}"

# Credentials come from the setup's own chain unless already provided.
if [ -z "${OPENROUTER_API_KEY:-}" ] && command -v pi >/dev/null 2>&1; then
  OPENROUTER_API_KEY="$(pi auth print-api-key --provider openrouter 2>/dev/null || true)"
  export OPENROUTER_API_KEY
fi

slug=$(echo "$MODEL" | tr '/:' '__')
RUN_ID="$(date +%Y%m%d-%H%M%S)_${HARNESS}_${slug}_seed${SEED}"
RUN_DIR="$PWD/results/$RUN_ID"
mkdir -p "$RUN_DIR"
ln -sfn "$RUN_DIR" "$PWD/results/latest-$HARNESS"
[ "$HARNESS" = "pi" ] && ln -sfn "$RUN_DIR" "$PWD/results/latest"

case "$HARNESS" in
  pi|p)   AGENT_VERSION="$(pi --version 2>/dev/null | tail -1)" ;;
  occ)    AGENT_VERSION="$(claude --version 2>/dev/null | head -1)" ;;
  ocdx)   AGENT_VERSION="$(codex --version 2>/dev/null | head -1)" ;;
esac
jq -n --arg model "$MODEL" --arg seed "$SEED" --arg harness "$HARNESS" --arg ver "$AGENT_VERSION" \
  '{model:$model, seed:$seed, harness:$harness, agentVersion:$ver, piVersion:$ver, startedAt:(now|todate)}' \
  > "$RUN_DIR/meta.json"

pids=()
for t in t1 t2 t3 t4 t5 t6 t7; do
  TASK=$t RUN_DIR="$RUN_DIR" SEED="$SEED" MODEL="$MODEL" HARNESS="$HARNESS" \
    bash harness/launch-task.sh > "$RUN_DIR/$t.console.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL TASKS DONE run=$RUN_ID harness=$HARNESS fail=$fail"
