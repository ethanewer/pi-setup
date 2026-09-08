#!/usr/bin/env bash
# Publish v3.5: the v3.4 tree with three vacuous verifiers repaired and their
# records re-run.
#
# The negative control -- every task run through harbor's nop agent, whose setup()
# and run() are both `pass`, so the verifier grades a pristine container -- found
# three tasks that awarded reward 1 for no work at all. All six pairs held a
# spurious 1 for each, so eighteen records are replaced.
#
# An oracle census cannot find this class. It runs each task's own reference
# solution, which does the work, so a verifier that always writes 1 passes that
# census at 785/785 while measuring nothing.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

GLM_PATH="z-ai/glm-5.3-flash"
DSK_PATH="deepseek/deepseek-v4-flash-0731"
GLM_META="openrouter/z-ai/glm-5.3-flash"
DSK_META="openrouter/deepseek/deepseek-v4-flash-0731"

SPECS=(
  "v35-pi-glm:pi:$GLM_PATH:$GLM_META"
  "v35-pi-dsk:pi:$DSK_PATH:$DSK_META"
  "v35-t2-glm:terminus-2:$GLM_PATH:$GLM_META"
  "v35-t2-dsk:terminus-2:$DSK_PATH:$DSK_META"
  "v35-claude-glm:claude-code:$GLM_PATH:$GLM_PATH"
  "v35-claude-dsk:claude-code:$DSK_PATH:$DSK_PATH"
)

ARGS=(--version v3.5
      --mirror /tmp/hf-upload/v3.4
      --out /tmp/hf-upload/v3.5
      --jobs-dir "$JOBS"
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --extra /tmp/v35_negative_control.json
      --note "v3.5 = the v3.4 tree with three vacuous verifiers repaired and their eighteen records re-run. The suite is unchanged at 785 tasks; only drift-marsh, opal-basin and pale-heron differ. Every other record is carried forward from v3.4 byte for byte."
      --note "A negative control was run over the whole suite: every one of the 785 tasks through harbor's nop agent, whose setup() and run() are both pass, so the verifier grades a pristine container in which no agent worked. All 785 produced a reward and none was left unscoreable. Three tasks awarded reward 1 anyway -- pale-heron, drift-marsh and opal-basin -- meaning their verifiers were vacuous and every pair had been scoring 1 on them regardless of performance, in v3.2 through v3.4."
      --note "An oracle census cannot find this class of defect, which is why the negative control matters. The census runs each task's own reference solution, which does the work; a verifier that always writes 1 passes that census at 785/785 while measuring nothing. Both halves are needed: the census proves the verifier accepts a correct solution, the negative control proves it rejects the absence of one."
      --note "pale-heron and drift-marsh shared one shape: a python heredoc that on failure wrote 0 to reward.txt and then exited 0, followed by a shell epilogue deriving its own reward from that status and writing the same file again. Because the failure path exited 0, the epilogue read success and overwrote the 0 with a 1. Both failure paths now exit 1, and a static scan for the pattern finds none remaining across the 16 verifiers that derive reward this way."
      --note "opal-basin was subtler. ref_texts was initialised to None and the try block that followed imported torch, loaded the tokenizer and model, and defined reference() -- but never called it, so the sentinel stayed None forever. Because the whole deliverable section is gated on 'if ref_texts is not None', roughly sixty lines never executed: /app/score.py, /app/refresh.sh and its executable bit, the runtime-derived manifest, the ready flag, every hidden text case. The verifier collapsed to a vendor-script hash check. The missing assignment is added; nop now scores 0 with five real failures and the oracle still scores 1."
      --note "The control also exposed a latent binary-contract violation in v1-item-019-main, which captured its heredoc's stdout into the reward while three early paths printed a diagnostic to stdout and raised SystemExit -- a BaseException, so the handler printing 0 never ran, and reward.txt received the text 'recovered db missing'. Its published records are unaffected (real agents reach the success path, and all six hold a canonical 1), but the diagnostics now go to stderr beside a numeric verdict and the epilogue writes only 0 or 1. check_binary_reward.py had reported this task BINARY: its print-seed extractor took the rest of the line, yielding a compound string no classifier recognised, and classify_expr only flagged arithmetic patterns. Both are fixed, with two new self-test fixtures taking it from 23 to 25."
      --note "The contamination audit was re-run over the current 785-task tree against the frozen tb2.1 reference, re-fetched at the pinned commit and verified byte-identical (241 tasks, 2059 files, task_checkout_sha256 matching). Over 13,610 authored payloads: 0 exact, 0 canary and 0 source-repository matches. The 5 block, 8 n-gram and 575 soft matches were each inspected and are recorded with their overlapping bytes in independence_report.json -- 32-64 byte windows of Dockerfile, GitHub Actions, bash and numpy idiom, plus two Apache-2.0 license sentences shared with Debian copyright files. Five vendored distributions were skipped on a verified sha256 match against their upstream source."
      --note "Both timeout conventions remain published per pair. The leaderboard is verifier-authoritative; results.json also carries the strict variant where any agent_timeout counts 0. The choice reorders the table, so it is stated rather than left implicit."
)

echo "=== [$(date -Is)] publishing v3.5 ==="
printf '  %s\n' "${SPECS[@]}"
REQUIRE=()
while read -r T; do
  [ -n "$T" ] && REQUIRE+=(--require-rerun "$T")
done < /tmp/v35_rerun_tasks.txt
echo "  requiring fresh records for $(wc -l < /tmp/v35_rerun_tasks.txt) repaired tasks x 6 pairs"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}" "${REQUIRE[@]}" \
  $(for s in "${SPECS[@]}"; do printf -- '--job %q ' "$s"; done)
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
