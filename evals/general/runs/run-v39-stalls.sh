#!/usr/bin/env bash
# Re-run eleven trials that never measured anything, in the two remaining pairs.
#
# Same defect as the eight terminus-2 trials re-run for v3.8, found by looking for
# records whose published transcript is empty rather than for records whose tool
# messages are empty:
#
#   claude-code/z-ai/glm-5.3-flash, 6 tasks -- the agent emitted one assistant
#     message and then hung mid-stream. The log is 0.6-6.2 MB, but 31,983 of
#     31,986 lines in hinge-lathe's are {"type":"system","subtype":"thinking_tokens"}
#     heartbeats with estimated_tokens creeping 1..19, so the size is a token
#     counter spinning, not transcript. No tool use, no tool result.
#
#   pi/deepseek, 5 tasks -- the log ends at message_end for the user prompt. No
#     assistant message was ever produced, and agent/pi/sessions/ was never written,
#     so there is no session jsonl to collect from.
#
# All six claude-code trials come from general-claude-glm and all five pi trials
# from general-pi-dsk, the same v3.2-era run window that produced the eight
# terminus-2 stalls in general-terminus-dsk. Nineteen identical failures clustered
# in one run window across three harnesses is a provider outage, not nineteen
# coincidences.
#
# Each burned its full agent budget (1200-1800 s) waiting and scored 0 under
# TIMEOUT_FAIL, so those zeros charge a provider outage to the model. A legitimate
# timeout -- the agent worked and did not finish in time -- is a real result and is
# not re-run; these issued no command and produced no assistant turn, so nothing
# was worked on.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
ROOT=/home/ee/general-eval-runs/v39-tasks
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a

CC_TASKS="gale-quarry sable-quill ashen-vane furnace-tide aurora-reef hinge-lathe"
PI_TASKS="saffron-chain umber-gasket coral-wheel glass-reef basalt-buoy"

mkset () { # name  tasks...
  local name="$1"; shift
  rm -rf "$ROOT/$name"; mkdir -p "$ROOT/$name"
  for t in "$@"; do ln -sfn "$EVAL/tasks/$t" "$ROOT/$name/$t"; done
  echo "[v39] $name: $(ls "$ROOT/$name" | wc -l) tasks"
}

report () { # jobname
  for d in "$OUT/$1"/*__*/; do
    [ -d "$d" ] || continue
    echo "[v39]   $(basename "$d") reward=$(cat "${d}verifier/reward.txt" 2>/dev/null || echo ABSENT) exc=$(python3 -c "
import json
try: print((json.load(open('${d}result.json')).get('exception_info') or {}).get('exception_type') or 'none')
except Exception: print('?')")"
  done
}

mkset cc-glm $CC_TASKS
mkset pi-dsk $PI_TASKS

# Three concurrent each, six at a time. The oracle census needs <=5 concurrent
# BUILDS because Debian mirrors throttle apt-get past that, but these tasks' images
# are long cached, so no archive traffic is expected. Kept at six rather than
# higher so a throttle would show up as a retryable error rather than a wide mess.
echo "[v39] $(date -Is) START claude-code/glm (6 tasks)"
"$HARBOR" run -p "$ROOT/cc-glm" -n 3 -k 1 -y -q --job-name v39-cc-glm-stalls -o "$OUT" \
  -a claude-code -m "z-ai/glm-5.3-flash" > "$OUT/v39-cc-glm-stalls.harness.log" 2>&1
echo "[v39] $(date -Is) claude-code rc=$?"
report v39-cc-glm-stalls

echo "[v39] $(date -Is) START pi/deepseek (5 tasks)"
"$HARBOR" run -p "$ROOT/pi-dsk" -n 3 -k 1 -y -q --job-name v39-pi-dsk-stalls -o "$OUT" \
  -a p_agent:PAgent -m "openrouter/deepseek/deepseek-v4-flash-0731" \
  > "$OUT/v39-pi-dsk-stalls.harness.log" 2>&1
echo "[v39] $(date -Is) pi rc=$?"
report v39-pi-dsk-stalls

echo "V39_DONE"
