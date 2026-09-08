#!/usr/bin/env bash
# Oracle sweep over the ENTIRE suite. A task whose own reference solution cannot
# pass its own verifier is broken regardless of what any agent scored on it, so
# this is the definitive defect census rather than a sample of never-passed tasks.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/all
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
rm -rf "$SET"; mkdir -p "$SET" "$OUT"
n=0
for d in "$EVAL"/tasks/*/; do
  t=$(basename "$d")
  ln -sfn "$d" "$SET/$t"; n=$((n+1))
done
echo "[postcensus] $(date -Is) START $n tasks"
"$HARBOR" run -p "$SET" -n 12 -k 1 -y -q \
  --job-name v34-oracle-post -o "$OUT" -a oracle \
  > "$OUT/v34-oracle-post.harness.log" 2>&1
rc=$?
echo "[postcensus] $(date -Is) DONE rc=$rc"
