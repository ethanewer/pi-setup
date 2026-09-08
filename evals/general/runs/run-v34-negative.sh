#!/usr/bin/env bash
# Negative control over the whole suite: run every task with harbor's nop agent,
# which does nothing at all, so the verifier grades a pristine container.
#
# The oracle census proves each verifier ACCEPTS a correct solution. It cannot
# prove the verifier REJECTS an incorrect one -- a verifier that always wrote 1
# would pass that census at 785/785. This is the other half, and it is the half
# that was never run: only 2 of 785 coverage claims record a negative check, and
# there is no tool for it. Any task scoring 1 here awards reward for no work.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/negative
LOG=/tmp/v34-negative.progress
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
rm -rf "$SET"; mkdir -p "$SET" "$OUT"
for d in "$EVAL"/tasks/*/; do ln -sfn "$d" "$SET/$(basename "$d")"; done
n=$(find "$SET" -mindepth 1 -maxdepth 1 | wc -l)
: > "$LOG"
echo "[negative] $(date -Is) START $n tasks with the nop agent" | tee -a "$LOG"
"$HARBOR" run -p "$SET" -n 12 -k 1 -y -q \
  --job-name v34-negative-control -o "$OUT" -a nop \
  > "$OUT/v34-negative-control.harness.log" 2>&1
echo "[negative] $(date -Is) DONE rc=$?" | tee -a "$LOG"
