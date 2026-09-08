#!/usr/bin/env bash
# Re-run hollow-notch for all six pairs after removing its DNS sabotage.
#
# The task used to fragment /etc/nsswitch.conf to "hosts: files", which disabled
# DNS inside the container. Two of the three harnesses run their agent CLI inside
# that container, so they could not reach the LLM API at all: claude-code retried
# ten times and gave up with UnknownApiError, pi emitted four assistant messages
# with null content. Four of six pairs scored 0 without making a single model
# call. Only terminus-2 was unaffected, because harbor drives its tmux from the
# host. Verified by building the image and running curl in it: "Could not resolve
# host: openrouter.ai".
#
# All six pairs are re-run, not just the four that were broken, because the task
# changed. Leaving terminus-2's two records on the old task would compare a
# different task against the other four pairs.
#
# The fix is minimal and was verified to preserve the challenge: the site FQDN
# still does not resolve (there is no DNS zone for hollow.farm, so the agent must
# add it to /etc/hosts), the postfix relayhost sabotage is intact, and
# tests/check.py still asserts the nsswitch hosts line contains files and dns.
# What the task loses is the sub-check for detecting a fragmented nsswitch line,
# which four of six pairs could never reach anyway.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
ROOT=/home/ee/general-eval-runs/v40-tasks/hollow-notch
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a

rm -rf "$ROOT"; mkdir -p "$ROOT"; ln -sfn "$EVAL/tasks/hollow-notch" "$ROOT/hollow-notch"

run () { # jobname agent model
  echo "[hn] $(date -Is) START $1  agent=$2  model=$3"
  # claude-code reaches OpenRouter through these two, which run-all.sh exports.
  export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
  export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
  "$HARBOR" run -p "$ROOT" -n 1 -k 1 -y -q --job-name "$1" -o "$OUT" \
    -a "$2" -m "$3" > "$OUT/$1.harness.log" 2>&1
  echo "[hn] $(date -Is) $1 rc=$?"
  python3 "$EVAL/tools/check_agent_actually_ran.py" --job "$OUT/$1" | tail -6
}

GLM_OR='openrouter/z-ai/glm-5.3-flash'
DSK_OR='openrouter/deepseek/deepseek-v4-flash-0731'

run v40-hn-cc-glm   claude-code    'z-ai/glm-5.3-flash'
run v40-hn-cc-dsk   claude-code    'deepseek/deepseek-v4-flash-0731'
run v40-hn-pi-glm   p_agent:PAgent "$GLM_OR"
run v40-hn-pi-dsk   p_agent:PAgent "$DSK_OR"
run v40-hn-t2-glm   terminus-2     "$GLM_OR"
run v40-hn-t2-dsk   terminus-2     "$DSK_OR"

echo "[hn] $(date -Is) all six pairs done"
echo "HN_DONE"
