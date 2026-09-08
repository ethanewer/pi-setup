#!/bin/bash
# Smoke test: one pi/glm trial on prism-ledge, to validate the harbor toolchain,
# the OpenRouter key, and the bench-base images before committing to 22 rollouts.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
export PYTHONPATH=$EVAL/agents
cd "$EVAL"

echo "[smoke] $(date -Is) START"
"$HARBOR" run \
  -p /home/ee/general-eval-runs/v33-tasks/smoke \
  -n 1 -k 1 -y -q \
  --job-name v33-smoke -o "$OUT" \
  -a p_agent:PAgent -m "openrouter/z-ai/glm-5.3-flash" \
  > "$OUT/v33-smoke.harness.log" 2>&1
rc=$?
echo "[smoke] $(date -Is) DONE rc=$rc"
echo "[smoke] --- harness log tail ---"
tail -25 "$OUT/v33-smoke.harness.log"
echo "[smoke] --- trial artifacts ---"
find "$OUT/v33-smoke" -maxdepth 3 -type f 2>/dev/null | head -20
echo "[smoke] --- reward ---"
find "$OUT/v33-smoke" -name reward.txt -exec sh -c 'echo "{}: $(cat {})"' \; 2>/dev/null
echo "[smoke] SMOKE_FINISHED rc=$rc"
