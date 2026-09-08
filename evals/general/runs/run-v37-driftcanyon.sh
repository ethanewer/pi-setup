#!/usr/bin/env bash
# drift-canyon's two terminus-2 records are the only ones whose raw trial directory
# no longer exists, so their dropped observations and reasoning cannot be recovered
# from disk. Re-run the task for both terminus-2 pairs so the published transcript
# is complete rather than publishing a record known to be missing its tool traffic.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v37-tasks/drift-canyon
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a
GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
rm -rf "$SET"; mkdir -p "$SET"
ln -sfn "$EVAL/tasks/drift-canyon" "$SET/drift-canyon"
for spec in "v37-t2-glm:$GLM" "v37-t2-dsk:$DSK"; do
  name=${spec%%:*}; m=${spec#*:}
  echo "[drift-canyon] $(date -Is) LAUNCH $name"
  "$HARBOR" run -p "$SET" -n 1 -k 1 -y -q --job-name "$name" -o "$OUT" \
    -a terminus-2 -m "$m" > "$OUT/$name.harness.log" 2>&1
  d=$(ls -d "$OUT/$name"/drift-canyon__*/ 2>/dev/null | head -1)
  echo "[drift-canyon]   $name reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT)"
done
echo "DRIFTCANYON_DONE"
