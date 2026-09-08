#!/usr/bin/env bash
# Publish v3.7: the v3.6 records with 80 terminus-2 transcripts restored.
#
# No reward changes. Every one of the 80 records was verified to carry the same
# reward as v3.6 before this was assembled; what changes is that the transcript
# now contains the commands the agent ran, the output it saw and its reasoning,
# which norm_t2 used to discard.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

ARGS=(--version v3.7
      --mirror /tmp/hf-upload/v3.6
      --overlay /tmp/t2-recovery
      --overlay /tmp/t2-driftcanyon
      --out /tmp/hf-upload/v3.7
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --extra /tmp/v35_negative_control.json
      --extra /tmp/v36_dependency_pins.json
      --extra /tmp/v37_transcript_recovery.json
      --note "v3.7 = the v3.6 tree with 80 terminus-2 transcripts restored. 785 tasks, six pairs, 4,710 records, every reward exactly 0 or 1. NO REWARD CHANGED: all 80 were diffed against v3.6 before assembly and carry the same reward. What changed is that the transcript now contains what the model was actually sent."
      --note "collect_task_records.py's terminus-2 path kept only each step's assistant prose. harbor writes the same ATIF-style steps for terminus-2 as for claude-code -- message, reasoning_content, tool_calls, and an observation holding the tool results fed back to the model -- and norm_claude and norm_pi both mapped all of them, but norm_t2 mapped one. So 80 of the 1,570 terminus-2 records, spanning 46 tasks across both models, published the assistant's reasoning prose and nothing else: no bash commands issued, no command output observed, no tool calls, no chain of thought. For vine-helix that was 8 published messages against 15 real ones and 16.7 KB against 162.5 KB."
      --note "The gap hid in the aggregate. The other 1,490 terminus-2 records were collected by an older code path and are complete, so dataset-wide message and byte totals looked healthy while every record collected since v3.3 was lossy. Found by comparing one published trajectory against its raw harbor trial: 272.5 KB raw against 15.7 KB published."
      --note "Restored by re-collecting from the raw trials, which are still on disk for 78 of the 80 across twelve job directories. Verified after re-collection: 0 reward differences, 70 records richer, 8 unchanged, 0 leaner, and byte-level fidelity on a full record -- tool observations 31,984 chars both sides, reasoning_content 98,181 both, tool_call arguments 12,126 both, opening user message 10,700 both, every ratio exactly 1.0000, so nothing is truncated."
      --note "drift-canyon is the one task whose two terminus-2 trial directories no longer existed, so its dropped content could not be recovered from disk. Both were re-run rather than published as transcripts known to be incomplete. Both timed out again at drift-canyon's 1800s agent budget and both score 0, exactly as published, so the re-run changed no verdict -- but the transcripts went from 9 messages and 16.8 KB to 17 and 328.9 KB for glm, and from 36 and 34.5 KB to 45 and 565.8 KB for deepseek."
      --note "Two smaller metadata gaps were fixed in the same pass, both adding fields rather than removing any. The exception field held only the type, so AgentTimeoutError did not say which budget was exhausted even though the timeout is a property of the task rather than the harness; 701 of the 742 published records carrying an exception already stored the Type: message form and 41 came from an older collector version. And reward_provenance was unset where the verifier returned a verdict despite an agent timeout, so a reader could not distinguish a TIMEOUT_FAIL zero from a graded zero."
      --note "Still not saved, deliberately: per-step step_id, timestamp, model_name and per-step token metrics. Aggregate final_metrics is carried. Adding the per-step fields would make these 80 records structurally different from the 1,490 already-complete terminus-2 records and from pi and claude-code, and message content -- which is verbatim -- was the gap being closed."
      --note "The leaderboard is unchanged from v3.6 and v3.5. Both timeout conventions remain published per pair: verifier-authoritative as the headline, with the strict variant where any agent_timeout counts 0 alongside it in results.json."
)

echo "=== [$(date -Is)] publishing v3.7 ==="
echo "  overlays: /tmp/t2-recovery ($(find /tmp/t2-recovery -name trajectory.json | wc -l) records), /tmp/t2-driftcanyon ($(find /tmp/t2-driftcanyon -name trajectory.json | wc -l) records)"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}"
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
