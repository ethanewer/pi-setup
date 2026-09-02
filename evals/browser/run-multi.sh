#!/usr/bin/env bash
# Arms x models in parallel (each owns its pihome); seeds sequential inside run.sh.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
MODELS="${MODELS:-openrouter/z-ai/glm-5.3-flash}"
ARMS="${ARMS:-agent-browser agent-browser-guided playwright devtools cli-agent-browser cli-playwright}"
SEEDS="${SEEDS:-101 202 303}"
pids=()
for arm in $ARMS; do
  for model in $MODELS; do
    ms=$(echo "$model" | tr '/:~' '___')
    echo "launching arm=$arm model=$ms"
    ARM="$arm" MODEL="$model" SEEDS="$SEEDS" ./run.sh > "results/arm-${arm}-${ms}.log" 2>&1 &
    pids+=($!)
  done
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL ARMS DONE (fail=$fail)"
