#!/usr/bin/env bash
# harbor-gasket's first re-run died on the known tmux flake -- "no server running
# on /tmp/tmux-0/default" at step 18, the tmux server vanishing mid-run. That is
# infrastructure, not the agent or the task, and it is the same failure class
# retried for v3.4 rather than scored.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v38-tasks/harbor-gasket
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a
rm -rf "$SET"; mkdir -p "$SET"; ln -sfn "$EVAL/tasks/harbor-gasket" "$SET/harbor-gasket"
echo "[gasket] $(date -Is) START harbor-gasket, terminus-2 + deepseek (retry 2)"
"$HARBOR" run -p "$SET" -n 1 -k 1 -y -q --job-name v38-t2-dsk-gasket -o "$OUT" \
  -a terminus-2 -m "openrouter/deepseek/deepseek-v4-flash-0731" \
  > "$OUT/v38-t2-dsk-gasket.harness.log" 2>&1
echo "[gasket] $(date -Is) DONE rc=$?"
for d in "$OUT"/v38-t2-dsk-gasket/*__*/; do
  [ -d "$d" ] || continue
  echo "[gasket]   reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT) steps=$(python3 -c "
import json
try: print(len(json.load(open('${d}agent/trajectory.json')).get('steps',[])))
except Exception: print('?')") exc=$(python3 -c "
import json
try: print((json.load(open('${d}result.json')).get('exception_info') or {}).get('exception_type') or 'none')
except Exception: print('?')")"
done
echo "GASKET_DONE"
