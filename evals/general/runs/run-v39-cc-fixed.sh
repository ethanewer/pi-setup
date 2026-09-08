#!/usr/bin/env bash
# Re-run the six claude-code/glm never-measured trials, with the environment the
# original run used.
#
# The first attempt (v39-cc-glm-stalls) was invalid and is quarantined, not
# published. It omitted two exports that run-all.sh sets for this pair:
#
#     export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
#     export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
#
# Without them claude-code never reached OpenRouter. The evidence is in the trial
# log: the model came through as bare "glm-5.3-flash" instead of
# "z-ai/glm-5.3-flash", and the single assistant message it produced was
# model:"<synthetic>" with input_tokens:0, output thinking_tokens:0,
# duration_api_ms:0 and total_cost_usd:0, then the CLI exited 1. Five of six
# trials failed identically with NonZeroAgentExitCodeError and the sixth with
# AgentSetupTimeoutError. Those zeros measured nothing and must not be published.
#
# The guard at the end is the point of this script. A silent no-op run looks
# exactly like a run where the model did badly, and the only thing separating them
# is whether the API was actually called. So check token usage and cost in the
# trial log, and refuse to report success if they are all zero.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
ROOT=/home/ee/general-eval-runs/v39-tasks
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a

# OpenRouter's Anthropic-compatible endpoint, exactly as run-all.sh sets it.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
[ -n "$ANTHROPIC_API_KEY" ] || { echo "FATAL: OPENROUTER_API_KEY empty"; exit 1; }
echo "[v39cc] ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL  key set: yes"

TASKS="gale-quarry sable-quill ashen-vane furnace-tide aurora-reef hinge-lathe"
rm -rf "$ROOT/cc-glm"; mkdir -p "$ROOT/cc-glm"
for t in $TASKS; do ln -sfn "$EVAL/tasks/$t" "$ROOT/cc-glm/$t"; done
echo "[v39cc] $(date -Is) START claude-code/glm, $(ls "$ROOT/cc-glm" | wc -l) tasks"

"$HARBOR" run -p "$ROOT/cc-glm" -n 3 -k 1 -y -q --job-name v39-cc-glm-fixed -o "$OUT" \
  -a claude-code -m "z-ai/glm-5.3-flash" > "$OUT/v39-cc-glm-fixed.harness.log" 2>&1
echo "[v39cc] $(date -Is) harbor rc=$?"

echo "[v39cc] checking that the API was actually called"
python3 - <<'PY'
import json, re, sys
from pathlib import Path
job=Path('/home/ee/general-eval-runs/jobs/v39-cc-glm-fixed')
bad=[]
rows=[]
for d in sorted(job.glob('*__*/')):
    log=d/'agent/claude-code.txt'
    txt=log.read_text(errors='replace') if log.is_file() else ''
    inp=sum(int(x) for x in re.findall(r'"input_tokens":(\d+)', txt))
    think=sum(int(x) for x in re.findall(r'"thinking_tokens":(\d+)', txt))
    cost=sum(float(x) for x in re.findall(r'"total_cost_usd":([0-9.]+)', txt))
    synth=txt.count('"model":"<synthetic>"')
    full=len(re.findall(r'"model":"z-ai/glm-5\.3-flash"', txt))
    rw=d/'verifier/reward.txt'
    reward=rw.read_text().strip() if rw.is_file() else 'ABSENT'
    exc=''
    rj=d/'result.json'
    if rj.is_file():
        exc=(json.loads(rj.read_text()).get('exception_info') or {}).get('exception_type') or ''
    rows.append((d.name.split('__')[0], reward, exc or 'none', inp, think, round(cost,4), synth, full))
    if inp==0 and think==0 and cost==0:
        bad.append(d.name)
print('%-16s %-7s %-26s %8s %8s %8s %8s %6s' % ('task','reward','exception','in_tok','think','cost_usd','synthetic','full-slug'))
for r in rows: print('%-16s %-7s %-26s %8d %8d %8.4f %8d %6d' % r)
print()
if bad:
    print('INVALID: %d trial(s) show zero API usage, so the model was never called: %s' % (len(bad), bad))
    print('These must not be published.')
    sys.exit(1)
print('all %d trials show real API usage' % len(rows))
PY
guard=$?
echo "[v39cc] $(date -Is) guard rc=$guard"
echo "V39CC_DONE guard=$guard"
exit $guard
