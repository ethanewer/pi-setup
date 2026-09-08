#!/usr/bin/env bash
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/fixbatch5
rm -rf "$SET"; mkdir -p "$SET"
for t in vine-yonder kite-helix; do ln -sfn "$EVAL/tasks/$t" "$SET/$t"; done
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
"$HARBOR" run -p "$SET" -n 2 -k 1 -y -q --job-name v34-fix-batch5 -o "$OUT" -a oracle \
  > "$OUT/v34-fix-batch5.harness.log" 2>&1
echo "[batch5] rc=$?"
for t in vine-yonder kite-helix; do
  d=$(ls -d "$OUT"/v34-fix-batch5/${t}__*/ 2>/dev/null | head -1)
  echo "[batch5] $t reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT)"
  grep -E "FAIL|fail" "${d}verifier/test-stdout.txt" 2>/dev/null | head -5 | sed 's/^/[batch5]     /'
done
echo "BATCH5_DONE"
