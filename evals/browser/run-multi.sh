#!/usr/bin/env bash
# Harnesses x arms x models in parallel (each pi run owns its pihome); seeds
# sequential inside run.sh. Arms only apply to HARNESS=pi; p/occ/ocdx run
# their native surface once per model.
set -uo pipefail
cd "$(dirname "$0")"
HARNESSES="${HARNESSES:-pi}"
MODELS="${MODELS:-openrouter/z-ai/glm-5.3-flash}"
ARMS="${ARMS:-agent-browser agent-browser-guided playwright devtools cli-agent-browser cli-playwright}"
SEEDS="${SEEDS:-101 202 303}"
pids=()
for harness in $HARNESSES; do
  for model in $MODELS; do
    ms=$(echo "$model" | tr '/:~' '___')
    if [ "$harness" = "pi" ]; then
      for arm in $ARMS; do
        echo "launching harness=$harness arm=$arm model=$ms"
        HARNESS="$harness" ARM="$arm" MODEL="$model" SEEDS="$SEEDS" ./run.sh \
          > "results/${harness}-arm-${arm}-${ms}.log" 2>&1 &
        pids+=($!)
      done
    else
      echo "launching harness=$harness (native surface) model=$ms"
      HARNESS="$harness" ARM="none" MODEL="$model" SEEDS="$SEEDS" ./run.sh \
        > "results/${harness}-native-${ms}.log" 2>&1 &
      pids+=($!)
    fi
  done
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL RUNS DONE (fail=$fail)"
