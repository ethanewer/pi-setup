#!/usr/bin/env bash
# Oracle verification over every task repaired for v3.4. A repair is not a repair
# until the task's own reference solution earns reward 1 under harbor.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/verify
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
rm -rf "$SET"; mkdir -p "$SET"
while read -r T; do
  [ -z "$T" ] && continue
  ln -sfn "$EVAL/tasks/$T" "$SET/$T"
done < /tmp/v34_repaired.txt
n=$(find "$SET" -mindepth 1 -maxdepth 1 | wc -l)
echo "[verify] $(date -Is) START $n repaired tasks"
"$HARBOR" run -p "$SET" -n 8 -k 1 -y -q \
  --job-name v34-verify-repairs -o "$OUT" -a oracle \
  > "$OUT/v34-verify-repairs.harness.log" 2>&1
echo "[verify] $(date -Is) DONE rc=$?"
