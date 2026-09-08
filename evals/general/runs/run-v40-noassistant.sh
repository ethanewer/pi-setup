#!/usr/bin/env bash
# Re-run three claude-code trials whose transcripts contain no assistant turn.
#
#   hollow-notch / z-ai/glm-5.3-flash       UnknownApiError after 10 api_retry
#   hollow-notch / deepseek-v4-flash-0731   events, "error":"server_error" and
#                                           "error":"unknown", $0.000 cost, 0 output
#                                           tokens. A proven provider fault.
#   rust-bazaar / deepseek-v4-flash-0731    No assistant message at all: the
#                                           published transcript is two user
#                                           messages, the task prompt and harbor's
#                                           own nudge "[Your previous response had
#                                           no visible output. Please continue and
#                                           produce a user-visible response.]". The
#                                           API was reached -- 36,801 input tokens,
#                                           $0.184, stop_reason end_turn -- but
#                                           returned 2 output tokens and nothing
#                                           visible, twice.
#
# rust-bazaar is the judgement call and it is worth stating why it is being re-run
# when 22 comparable records are not. Those 22 all contain a real assistant turn,
# and eight of them contain a great deal of one: ashen-vane 24,270 output tokens,
# glass-reef 23,735, frost-latch 21,841, cobalt-fjord 16,863. quartz-wharf spent
# $0.835 and hit max_tokens producing only a thinking block. Those are poor
# results and they are real results, so re-running them would be re-rolling
# failures in one direction only. rust-bazaar produced no assistant turn at all,
# so there is no result to re-roll.
#
# If the re-run reproduces the empty output, the zero stands and is published as a
# reproducible model behaviour rather than a fault. That is what happened with
# ashen-lattice and vine-terrace in v3.8: both timed out again after 18 and 74
# steps of real work, and both zeros were kept.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
ROOT=/home/ee/general-eval-runs/v40-tasks
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a

# claude-code reaches OpenRouter through these two, which run-all.sh exports.
# Omitting them is what made the first v39 attempt a silent no-op.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
[ -n "$ANTHROPIC_API_KEY" ] || { echo "FATAL: OPENROUTER_API_KEY empty"; exit 1; }
echo "[v40] BASE_URL=$ANTHROPIC_BASE_URL key=yes"

run () { # jobname model tasks...
  local job="$1" model="$2"; shift 2
  rm -rf "$ROOT/$job"; mkdir -p "$ROOT/$job"
  for t in "$@"; do ln -sfn "$EVAL/tasks/$t" "$ROOT/$job/$t"; done
  echo "[v40] $(date -Is) START $job ($# tasks) model=$model"
  "$HARBOR" run -p "$ROOT/$job" -n "$#" -k 1 -y -q --job-name "$job" -o "$OUT" \
    -a claude-code -m "$model" > "$OUT/$job.harness.log" 2>&1
  echo "[v40] $(date -Is) $job rc=$?"
}

run v40-cc-glm-hollow      "z-ai/glm-5.3-flash"              hollow-notch
run v40-cc-dsk-hollowrust  "deepseek/deepseek-v4-flash-0731" hollow-notch rust-bazaar

echo "[v40] $(date -Is) gating the re-runs"
rc=0
for j in v40-cc-glm-hollow v40-cc-dsk-hollowrust; do
  echo "--- $j"
  python3 "$EVAL/tools/check_agent_actually_ran.py" --job "$OUT/$j" || rc=1
done
echo "[v40] $(date -Is) gate rc=$rc"
echo "V40_DONE gate=$rc"
exit $rc
