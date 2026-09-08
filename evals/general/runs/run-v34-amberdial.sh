#!/usr/bin/env bash
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/amberdial
rm -rf "$SET"; mkdir -p "$SET"
ln -sfn "$EVAL/tasks/amber-dial" "$SET/amber-dial"
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
"$HARBOR" run -p "$SET" -n 1 -k 1 -y -q --job-name v34-amber-dial -o "$OUT" -a oracle \
  > "$OUT/v34-amber-dial.harness.log" 2>&1
echo "[amber-dial] rc=$?"
d=$(ls -d "$OUT"/v34-amber-dial/amber-dial__*/ 2>/dev/null | head -1)
echo "[amber-dial] reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT)"
head -12 "${d}verifier/test-stdout.txt" 2>/dev/null | sed 's/^/[amber-dial]   /'
echo "AMBERDIAL_DONE"
