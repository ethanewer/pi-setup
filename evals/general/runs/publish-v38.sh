#!/usr/bin/env bash
# Publish v3.8: the v3.7 tree with the whole terminus-2 corpus re-collected and
# eight never-measured trials replaced by re-runs.
#
# Six rewards change, all 0 -> 1, all on terminus-2/deepseek, and all for the same
# reason: the trial being replaced had timed out inside harbor's _query_llm having
# issued no command at all. No other pair moves. pi and claude-code records are
# byte-identical to v3.7.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

ARGS=(--version v3.8
      --mirror /tmp/hf-upload/v3.7
      --overlay /tmp/t2-v38
      --out /tmp/hf-upload/v3.8
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --extra /tmp/v35_negative_control.json
      --extra /tmp/v36_dependency_pins.json
      --extra /tmp/v37_transcript_recovery.json
      --extra /tmp/v38_transcript_recovery.json
      --note "v3.8 = the v3.7 tree with all 1,570 terminus-2 records re-collected from the trial each one already names as its source, plus eight never-measured trials replaced by re-runs. 785 tasks, six pairs, 4,710 records, every reward exactly 0 or 1."
      --note "SIX REWARDS CHANGE, all 0 to 1, all on terminus-2/deepseek, which goes from 608 to 614. No other pair moves and no reward was re-graded. Each of the six is a trial that had timed out inside harbor's _query_llm waiting for a first LLM response that never arrived, having issued no command whatsoever; when the model actually answered, it solved the task. The remaining two of those eight, ashen-lattice and vine-terrace, timed out again after 18 and 74 steps of real work, so those zeros are legitimate results and stand."
      --note "CORRECTION TO v3.7. v3.7 reported that 1,490 terminus-2 records were already complete and that only 80 needed restoring. That was wrong, and the error was in the detector rather than the fix. v3.7 flagged records carrying no tool message, no tool call and no reasoning at all, but the older collection path emitted one tool message per tool_call and left its content EMPTY when no observation matched. Those records passed the test while holding nothing."
      --note "Measured on content rather than counts: the pre-v3.8 terminus-2 corpus carried 21,040 tool messages of which 17,021 -- 81% -- were empty shells, holding 10.1 MB of terminal output. Re-collected, the same trials yield 13,086 tool messages, none empty, holding 28.0 MB, a gain of 2.76x. 1,471 records gained content and none lost any. Counting messages is what made this invisible; counting bytes is what found it."
      --note "The eight stalled trials were all from one job, general-terminus-dsk, and all had the same signature: one recorded step (the opening prompt), a 326-376 byte pane containing only the harness's own clear, and six asciinema events inside the first second. Eight identical failures in one job is a provider outage window, not eight coincidences. Their reward of 0 had been charging that outage to the model under the TIMEOUT_FAIL rule."
      --note "A legitimate timeout is a real result and is not re-run. These were not legitimate timeouts, because nothing was worked on. That distinction is what keeps this from being a re-roll of failures: ashen-lattice and vine-terrace were re-run too and both timed out again after substantial work, and both zeros were kept."
      --note "harbor-gasket's first re-run died on the known tmux flake, RuntimeError 'no server running on /tmp/tmux-0/default' at step 18, and needed a second attempt. The collector refused to publish that trial because it had no reward.txt, which is the guard working as intended rather than a defect."
      --note "Two schema representations changed for terminus-2 assistant messages, neither altering substance. Content moves from a bare string to the [{'type':'text','text':...}] part form, and tool_call arguments from a JSON-encoded string to a dict matching pi. Measured across all 1,570 records: 11,095 content differences and 10,315 argument differences are container form only, with zero cases where the decoded text or the decoded arguments actually differ. pi and claude-code already publish both forms, so this adds no new heterogeneity."
      --note "Eleven records lose reasoning_content, and in every one the published reasoning was a verbatim duplicate of that same message's text: the older path copied Analysis prose into the reasoning field. Zero genuine reasoning losses."
      --note "64 reward.txt files came out of the collector in float form and were binarized under the documented rule, new = 1 exactly where old >= 1.0. Nine raw rewards were genuinely fractional (0.70, 0.80, 0.5) and binarize to 0, matching what v3.7 already published, so none of these is a semantic change."
      --note "pi and claude-code were checked for the same defect and are not affected. claude-code has zero observation steps without tool_calls, so its tool messages were never left empty. pi reads a real session jsonl and maps toolResult to a tool message without gating on tool_calls, so it is structurally immune."
      --note "Every one of the 1,570 records was re-collected from the trial named in its own published source_trial, and selection matched 1,570 of 1,570, so no record can silently substitute a different attempt at the same task. harbor truncates task names in trial directories to 32 characters and drops a trailing hyphen, so selection is keyed on the trial id rather than the task name."
)

echo "=== [$(date -Is)] publishing v3.8 ==="
echo "  overlay: /tmp/t2-v38 ($(find /tmp/t2-v38 -name trajectory.json | wc -l) terminus-2 records)"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}"
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
