#!/usr/bin/env bash
# Publish v3.9: the v3.8 tree with eleven never-measured trials replaced by re-runs.
#
# TEN REWARDS CHANGE, all 0 -> 1: claude-code/glm 659 -> 664 and pi/deepseek
# 649 -> 654. No other pair moves and nothing was re-graded. The eleventh re-run,
# aurora-reef, timed out again after 8 real model turns and 3 tool calls, so its 0
# is a legitimate timeout and is kept.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

# Gate before publishing: every trial in the overlay must have reached the model.
echo "=== [$(date -Is)] gating the overlay ==="
GATE=(); while read -r t; do [ -n "$t" ] && GATE+=(--trial "$t"); done < /tmp/v39_trial_dirs.txt
python3 "$EVAL/tools/check_agent_actually_ran.py" "${GATE[@]}" || {
  echo "FATAL: a trial in the overlay never measured anything; refusing to publish v3.9" >&2
  exit 1; }

ARGS=(--version v3.9
      --mirror /tmp/hf-upload/v3.8
      --overlay /tmp/v39-overlay
      --out /tmp/hf-upload/v3.9
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
      --note "v3.9 = the v3.8 tree with eleven never-measured trials replaced by re-runs. 785 tasks, six pairs, 4,710 records, every reward exactly 0 or 1. The other 4,699 records are byte-identical to v3.8."
      --note "TEN REWARDS CHANGE, all 0 to 1: claude-code/glm 659 to 664 and pi/deepseek 649 to 654, total 3,885 to 3,895. No other pair moves and nothing was re-graded. The eleventh re-run, aurora-reef, timed out again after 8 real model turns and 3 tool calls, so its 0 is a legitimate timeout and is kept. That is the control case for the whole exercise."
      --note "The defect was eleven trials from the original v3.2 run window that timed out having produced no assistant turn at all. Six claude-code/glm trials emitted one assistant message and then hung mid-stream: hinge-lathe's log was 6.2 MB, but 31,983 of its 31,986 lines were thinking_tokens heartbeats with estimated_tokens creeping 1..19, so the size was a token counter spinning rather than transcript. Five pi/deepseek trials ended at message_end for the user prompt, with no assistant message and no session jsonl ever written. Each burned its full 1200-1800 s budget and scored 0 under TIMEOUT_FAIL, charging a provider outage to the model."
      --note "All six claude-code trials came from general-claude-glm and all five pi trials from general-pi-dsk, the same window that produced the eight terminus-2 stalls in general-terminus-dsk re-run for v3.8. Nineteen identical failures across three harnesses in one run window is an outage, not nineteen coincidences."
      --note "A legitimate timeout is a real result and is not re-run. These issued no command and produced no assistant turn, so nothing was worked on, and re-running them corrects an invalid record rather than re-rolling a failure. Sixteen of the nineteen across the three harnesses passed once the model answered."
      --note "The first re-run attempt at the six claude-code trials was invalid and is quarantined as v39-cc-glm-stalls-INVALID-noenv with an INVALID.md; it was never collected and never published. It omitted ANTHROPIC_API_KEY and ANTHROPIC_BASE_URL, which the original run exports for this pair, so claude-code never reached OpenRouter: the model arrived as bare glm-5.3-flash instead of z-ai/glm-5.3-flash and the single assistant message was model <synthetic> with input_tokens 0, thinking_tokens 0, duration_api_ms 0 and total_cost_usd 0, then the CLI exited 1. Five of six failed identically with NonZeroAgentExitCodeError. Nothing in the reward files distinguished that from a model that tried and lost, which is why the gate below now exists."
      --note "The second attempt produced four valid trials plus hinge-lathe (AgentSetupTimeoutError, zero-byte log, never started) and sable-quill (ApiConnectionClosedError after one synthetic turn and no tool use). Both were retried and both passed."
      --note "tools/check_agent_actually_ran.py gates this publish and was run over exactly the eleven trials being published; all eleven cleared it. Its first version summed input_tokens and total_cost_usd and wrongly condemned four valid claude-code runs, three of which had passed, because claude-code reports usage only in its final result event, which never lands when harbor kills the CLI on an agent timeout. ashen-vane did 58 real turns and 25 tool calls, reported zero usage, and passed. The corrected criterion counts real assistant turns and tool_use blocks, plus a separate infrastructure-exception class covering setup timeouts, dropped connections, non-zero CLI exits and a vanished tmux server. AgentTimeoutError is deliberately not in that class."
      --note "CORPUS COMPLETENESS IS NOW VERIFIED FOR ALL THREE HARNESSES, by content bytes against the raw trials rather than by message counts. claude-code publishes 63.77 MB of tool-result content against 63.77 MB in the raw trials, ratio 1.0000, with no record short. pi publishes 11.03 MB against 11.03 MB, ratio 1.0000, no record short. terminus-2 was re-collected in v3.8 and holds 28.0 MB with zero empty tool messages. The 24 claude-code and 2 pi empty tool messages are genuinely empty command output, present in the raw trials too."
      --note "Counting messages is what let 17,021 empty tool shells pass as complete in v3.7. Counting bytes is what found them, and that check is now run over all three harnesses rather than only the one that had already failed."
      --note "Four records cannot be re-verified against a raw trial: drift-canyon for claude-code and pi on both models, whose trial directories no longer exist. They carry 141, 94, 36 and 26 messages with 294.1, 114.8, 21.5 and 7.6 KB of tool content and zero empty tool messages, so they are demonstrably not stalls. terminus-2's drift-canyon trials were likewise gone and were re-run for v3.7."
)

echo "=== [$(date -Is)] publishing v3.9 ==="
echo "  overlay: /tmp/v39-overlay ($(find /tmp/v39-overlay -name trajectory.json | wc -l) records)"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}"
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
