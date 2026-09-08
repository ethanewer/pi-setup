#!/usr/bin/env bash
# Oracle sweep over the never-passed tasks that were not sampled for v3.3, to find
# which of them are broken tasks rather than hard tasks. Same method and same
# harbor as the v3.3 sweep: each task's own solution/solve.sh under harbor's
# oracle agent, no model, no LLM inference.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/never-passed
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
mkdir -p "$SET" "$OUT"
while read -r T; do
  [ -z "$T" ] && continue
  ln -sfn "$EVAL/tasks/$T" "$SET/$T"
done < /tmp/sweep_todo.txt
n=$(find "$SET" -mindepth 1 -maxdepth 1 | wc -l)
echo "[sweep2] $(date -Is) START $n tasks"
"$HARBOR" run -p "$SET" -n 6 -k 1 -y -q \
  --job-name v34-oracle-neverpassed -o "$OUT" -a oracle \
  > "$OUT/v34-oracle-neverpassed.harness.log" 2>&1
rc=$?
echo "[sweep2] $(date -Is) DONE rc=$rc"
