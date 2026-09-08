#!/usr/bin/env bash
# Re-run eight terminus-2/deepseek trials whose agent never received a single LLM
# response. All eight timed out inside harbor's _query_llm with one recorded step
# (the opening prompt), a 326-376 byte pane holding only the harness's own `clear`,
# and six asciinema events inside the first second. The agent issued no command at
# all, so the reward of 0 these records carry is an API stall charged to the model
# as though it were a timeout after work -- the same category as the two tmux
# flakes retried for v3.4, not a re-roll of a genuine failure.
#
# All eight come from one job, general-terminus-dsk, which is consistent with a
# provider outage window rather than eight independent coincidences.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v38-tasks/llm-stalls
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
rm -rf "$SET"; mkdir -p "$SET"
for t in ashen-lattice basalt-vault clover-anchor fen-lantern \
         harbor-gasket hazel-quarry teal-assembler vine-terrace; do
  ln -sfn "$EVAL/tasks/$t" "$SET/$t"
done
echo "[stalls] $(date -Is) START 8 tasks, terminus-2 + deepseek"
"$HARBOR" run -p "$SET" -n 4 -k 1 -y -q --job-name v38-t2-dsk-stalls -o "$OUT" \
  -a terminus-2 -m "$DSK" > "$OUT/v38-t2-dsk-stalls.harness.log" 2>&1
echo "[stalls] $(date -Is) DONE rc=$?"
for d in "$OUT"/v38-t2-dsk-stalls/*__*/; do
  [ -d "$d" ] || continue
  echo "[stalls]   $(basename "$d") reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT) steps=$(python3 -c "
import json,sys
try: print(len(json.load(open('${d}agent/trajectory.json')).get('steps',[])))
except Exception: print('?')" 2>/dev/null)"
done
echo "STALLS_DONE"
