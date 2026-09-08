#!/usr/bin/env bash
# Publish v3.10: the v3.9 tree with seven records replaced.
#
# FOUR REWARDS CHANGE, all 0 -> 1, all on hollow-notch, because that task no longer
# disables DNS inside its own container. No other task moves and nothing else was
# re-graded. The other three replaced records keep their zeros, which are now
# legitimate results rather than artifacts.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

echo "=== [$(date -Is)] gating the overlay ==="
GATE=(); while read -r t; do [ -n "$t" ] && GATE+=(--trial "$t"); done < /tmp/v40_trial_dirs.txt
python3 "$EVAL/tools/check_agent_actually_ran.py" "${GATE[@]}" || {
  echo "FATAL: a trial in the overlay never reached the model; refusing to publish v3.10" >&2
  exit 1; }

ARGS=(--version v3.10
      --mirror /tmp/hf-upload/v3.9
      --overlay /tmp/v40-overlay
      --out /tmp/hf-upload/v3.10
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --extra /tmp/v35_negative_control.json
      --extra /tmp/v36_dependency_pins.json
      --extra /tmp/v37_transcript_recovery.json
      --extra /tmp/v38_transcript_recovery.json
      --extra /tmp/v39_never_measured.json
      --extra /tmp/v40_hollow_notch.json
      --note "v3.10 = the v3.9 tree with seven records replaced. 785 tasks, six pairs, 4,710 records, every reward exactly 0 or 1. The other 4,703 records are byte-identical to v3.9."
      --note "FOUR REWARDS CHANGE, all 0 to 1, all on one task: hollow-notch for claude-code/glm, claude-code/deepseek, pi/deepseek and terminus-2/glm. Totals 3,895 to 3,899. No other task moves and nothing was re-graded. The cause is a task defect, not a model or a transcript: hollow-notch disabled DNS inside its own container, which disabled the agent."
      --note "TASK DEFECT. hollow-notch's Dockerfile fragmented /etc/nsswitch.conf to 'hosts: files', removing the dns fallback. Two of the three harnesses are installed agents whose CLI runs inside that container and calls the LLM API over the network, so the sabotage stopped the agent from making any model call at all. Proven by building the image and running curl in it: 'curl: (6) Could not resolve host: openrouter.ai'. getent fails for openrouter.ai, api.anthropic.com and downloads.claude.ai, while localhost still resolves because /etc/hosts is still consulted."
      --note "Effect per pair. claude-code retried the API ten times with error server_error and error unknown, gave up with UnknownApiError, and left a transcript of one synthetic assistant message and no real turn, costing \$0.000 with 0 output tokens, on both models. pi left four assistant messages with null content and null final_metrics, on both models. terminus-2 was unaffected because harbor drives its tmux session from the host, so its API calls never traverse the container resolver; it timed out on the task's own difficulty, which is a legitimate result. Four of the six measured pairs could not attempt the task, and their zeros were charged to the models as though they had tried."
      --note "The Dockerfile already anticipated a DNS problem and pre-baked the claude-code CLI so the harness agent-installer, which needs working DNS, would be skipped at trial time. That mitigation covers installation, which needs DNS once at build time, not operation, which needs it on every API call."
      --note "FIX. The nsswitch sabotage is removed and instruction.md corrected in three places so it no longer tells the agent to repair a breakage that is not there. The sabotage was redundant: there is no DNS zone for the invented hollow.farm, so the agent must add the site FQDN to /etc/hosts regardless of the nsswitch line, and that is where the task's name-resolution work actually lives. Verified after the fix: openrouter.ai resolves and curl to the API returns HTTP 200, while 'getent hosts palisade-core.hollow.farm' still FAILS, the postfix relayhost hijack is intact and the baked-in CLI is untouched. tests/check.py still asserts the hosts line contains files and dns, now as a guard against the agent breaking it rather than a repair it must perform. What the task loses is the sub-check for detecting a fragmented nsswitch line, which four of six pairs could never reach and so was not being measured anyway."
      --note "All six pairs were re-run, not only the four that were broken. The task changed, so leaving terminus-2's two records on the old version would compare a different task against the other four pairs. A grep over all 785 task environments found hollow-notch is the only task that fragments nsswitch or otherwise disables DNS."
      --note "Result. Four of six now pass. claude-code went from zero API calls to 48 and 104 real assistant turns with 42 and 80 tool calls, costing \$1.46 and \$3.94, and both pass. pi/deepseek went from four null messages to 22 turns and 30 tool calls and passes. terminus-2/glm now passes after 19 steps. Three zeros are kept and all three are now legitimate: pi/glm reaches the API and does work (3 turns, 2 tool calls) but fails the task; terminus-2/deepseek timed out again after 9 steps and 8 tool calls; claude-code/deepseek rust-bazaar did 86 turns and 64 tool calls and did not solve it."
      --note "The seventh replaced record is rust-bazaar for claude-code/deepseek, whose reward does NOT change. Its published transcript was two user messages and no assistant message at all: the task prompt, then harbor's own nudge '[Your previous response had no visible output. Please continue and produce a user-visible response.]'. The API had been reached -- 36,801 input tokens, \$0.184, stop_reason end_turn -- but returned 2 output tokens and nothing visible, twice. Re-run it produced 86 turns, 64 tool calls, 35,323 output tokens and \$2.06, and still scored 0. The zero was correct; the record was not a measurement, and now it is. The empty output did not reproduce, so it was a transient provider fault."
      --note "rust-bazaar was re-run while 21 comparable records were deliberately left alone. Those 21 all contain a real assistant turn, and eight contain a great deal of one: ashen-vane 24,270 output tokens, glass-reef 23,735, frost-latch 21,841, cobalt-fjord 16,863. quartz-wharf spent \$0.835 and hit max_tokens producing only a thinking block. Those are poor results and they are real results, so re-running them would re-roll failures in one direction only. rust-bazaar had no assistant turn to re-roll."
      --note "tools/check_agent_actually_ran.py gated this publish and was run over exactly the seven trials being published; all seven cleared it. It reports api_retry counts with their error strings, cost and output tokens alongside turn counts, because turn counts alone cannot separate hollow-notch (10 retries, \$0.00, 0 output tokens) from ashen-vane (24,270 output tokens, \$0.70) -- both have two or fewer assistant turns. An infrastructure exception invalidates a trial only if it hit before real work, so a trial with 25 tool calls that then lost its connection is not condemned alongside one that produced a single synthetic turn."
      --note "The gate's own history is recorded because it matters for reading these numbers. Its first version summed input_tokens and total_cost_usd and wrongly condemned four valid claude-code runs, three of which had passed, because claude-code reports usage only in its final result event and that event never lands when harbor kills the CLI on an agent timeout. ashen-vane did 58 real turns and 25 tool calls, reported zero usage, and passed. --job is now repeatable; it was not, and passing six job directories silently checked only the last one."
      --note "Corpus completeness was verified for all three harnesses by content bytes against the raw trials rather than by message counts: claude-code 63.77 MB published against 63.77 MB raw, ratio 1.0000, no record short; pi 11.03 MB against 11.03 MB, ratio 1.0000, no record short; terminus-2 re-collected in v3.8 holding 28.0 MB with zero empty tool messages. Counting messages is what let 17,021 empty tool shells pass as complete in v3.7. Four records cannot be re-verified against a raw trial, all drift-canyon, whose trial directories no longer exist; they carry 141, 94, 36 and 26 messages with 294.1, 114.8, 21.5 and 7.6 KB of tool content and zero empty tool messages, so they are demonstrably not stalls."
)

echo "=== [$(date -Is)] publishing v3.10 ==="
echo "  overlay: /tmp/v40-overlay ($(find /tmp/v40-overlay -name trajectory.json | wc -l) records)"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}"
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
