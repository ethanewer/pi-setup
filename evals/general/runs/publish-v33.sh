#!/usr/bin/env bash
# Publish v3.3 using the committed tools/publish_version.sh wrapper.
#
# Three groups of re-runs feed the overlay:
#   22  records v3.2 published with no verifier/reward.txt
#    6  v1-item-033-hard, verifier was structurally unsolvable (health mark
#       inverted), so its records no longer measure what the task says
#    6  v1-item-041-hard, base image put node where the verifier could not see
#       it, so passing depended on the agent fixing the environment
#
# The 37 fractional records are rescored arithmetically from their published
# value; the overlay replaces the 34 above.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
GLM_PATH="z-ai/glm-5.3-flash"
DSK_PATH="deepseek/deepseek-v4-flash-0731"
GLM_META="openrouter/z-ai/glm-5.3-flash"
DSK_META="openrouter/deepseek/deepseek-v4-flash-0731"

# job-name:harness:model-in-path:model-in-metadata
# Written out explicitly rather than generated: the original 22 re-runs span only
# five pairs (terminus-2/glm had none), while the two repaired tasks span all six,
# and the job names differ per group. Getting this wrong silently drops records.
# claude-code keeps the bare OpenRouter slug in metadata because harbor passes the
# whole -m string through as ANTHROPIC_MODEL.
SPECS=(
  "v33-pi-glm:pi:$GLM_PATH:$GLM_META"
  "v33-pi-dsk:pi:$DSK_PATH:$DSK_META"
  "v33-t2-dsk:terminus-2:$DSK_PATH:$DSK_META"
  # cedar-canyon is collected from the retry job, not v33-t2-dsk: its first
  # trial died with RewardFileNotFoundError because the verifier raised before
  # writing a reward, and that trial dir has been moved aside.
  "v33-t2-dsk-cedar:terminus-2:$DSK_PATH:$DSK_META"
  "v33-claude-glm:claude-code:$GLM_PATH:$GLM_PATH"
  "v33-claude-dsk:claude-code:$DSK_PATH:$DSK_PATH"
  "v33-033-pi-glm:pi:$GLM_PATH:$GLM_META"
  "v33-033-pi-dsk:pi:$DSK_PATH:$DSK_META"
  "v33-033-t2-glm:terminus-2:$GLM_PATH:$GLM_META"
  "v33-033-t2-dsk:terminus-2:$DSK_PATH:$DSK_META"
  "v33-033-claude-glm:claude-code:$GLM_PATH:$GLM_PATH"
  "v33-033-claude-dsk:claude-code:$DSK_PATH:$DSK_PATH"
  "v33-041h-pi-glm:pi:$GLM_PATH:$GLM_META"
  "v33-041h-pi-dsk:pi:$DSK_PATH:$DSK_META"
  "v33-041h-t2-glm:terminus-2:$GLM_PATH:$GLM_META"
  "v33-041h-t2-dsk:terminus-2:$DSK_PATH:$DSK_META"
  "v33-041h-claude-glm:claude-code:$GLM_PATH:$GLM_PATH"
  "v33-041h-claude-dsk:claude-code:$DSK_PATH:$DSK_PATH"
)

ARGS=(--version v3.3
      --mirror /tmp/v32-full/v3.2
      --out /tmp/hf-upload/v3.3
      --jobs-dir "$JOBS"
      --repo eewer/general-agent-bench-results
      --extra /tmp/never_passed.json
      --extra /tmp/oracle_defects.json
      --note "v3.3 = the v3.2 tree with every reward made binary, every unscoreable record re-run, and three task defects repaired. All six harness/model pairs cover all 787 suite tasks, and every record has all four files."
      --note "45 task verifiers awarded partial credit (41 v1-item-*, 3 v1-skill-*, zephyr-bridge); all now emit 0 or 1. Each was binarized at full credit, so the new reward is 1 exactly where the old score was >= 1.0 and the pass set is unchanged. Enforced statically by tools/check_binary_reward.py: 787/787 BINARY, with a 23-case self-test and a regression fixture of 18 pre-fix verifiers that still fail."
      --note "37 records across 11 tasks were rescored arithmetically from their published value with no model inference. 34 records were re-run with harbor 0.22.0 against the live suite: the 22 that v3.2 published with no verifier/reward.txt, plus 6 for v1-item-033-hard and 6 for v1-item-041-hard whose task definitions were repaired."
      --note "v1-item-033-hard was structurally unsolvable. Its verifier awards 7 marks and requires all 7, but the health mark was granted only when the server FAILED to start, while the other six were checked only in the else branch. Six of seven was the ceiling: five published pairs scored 0.80, one scored 0.00, none ever scored 1.0, and the oracle scored 0.80. Fixed and oracle-verified at reward 1."
      --note "v1-item-041-hard was built FROM bench-base:ubuntu-24.04, where node exists only under nvm and is not on PATH for a non-interactive shell, so the verifier's node tools/run.js exited 127 and full credit was unreachable. Its sibling v1-item-041-main has always used bench-base:node-22. Fixed and oracle-verified at reward 1. The two published claude-code runs that scored 1.0 did so only because those agents happened to put node on PATH themselves."
      --note "v1-item-044-main's oracle never committed its cherry-pick: the container sets no git identity, so git applied the change to the index and died with rc=128, leaving the fix staged and the tree dirty. All six published agent runs scored 1.0 because agents configure an identity when git complains, so no record was affected; only the reference solution was broken. Verified by replaying all seven checks against tests/fixtures: 7/7."
      --note "Agent timeouts are recorded rather than guessed. Harbor skips the verifier phase when an agent exhausts the task timeout_sec, which is how the 22 unscoreable records arose. Where the verifier never ran, the record carries reward 0 with agent_timeout true and a reward_provenance field naming the TIMEOUT_FAIL policy from audit_run_rewards.py. Where the verifier did run despite the timeout, its verdict is kept as-is, so reward.txt stays authoritative exactly as it is for every other record. agent_timeout is flagged in both cases, so a consumer who prefers the strict convention, under which any timeout scores 0, can recompute it without re-running anything. A VerifierTimeoutError is never scored 0, since that is the harness failing rather than the agent."
      --note "Verifiers now always write a reward. cedar-canyon imports the agent's /app/solve.py and calls solve.binding_prefix, and a submission lacking that attribute killed the verifier with AttributeError before it reached either reward write, so the trial finished with no verdict at all and harbor raised RewardFileNotFoundError. Four of the 22 unscoreable v3.2 records were that shape rather than an agent timeout. 705 of 787 verifiers had no protection, so all of them now carry the EXIT-trap guard 82 already used: it fires only when no reward was written, so it cannot change a verdict a verifier reached, and it turns no-verdict into 0 plus a diagnostic while the traceback still reaches test-stdout.txt. tools/ensure_reward_guard.py is a gate, so a new task cannot reintroduce this."
      --note "Carried-over records were produced by the pre-binarization verifiers. That is sound because only the reward computation changed, not the task instructions or environments, and old 1.0 maps to new 1 while old 0.0 maps to new 0. The two tasks whose definition actually changed were re-run instead."
      --note "First version to ship per-pair results.json aggregates. v3.2 shipped none, and the v3.1 aggregate it inherited for claude-code/glm said 647.50 where the reward files sum to 648.50."
      --note "Known outstanding: 59 tasks were never passed by any of the six pairs, so each is a 0 for every pair in v3.3. All 45 binarized verifiers were oracle-swept and 10 of the other 54 were sampled, using harbor's oracle agent, which runs each task's own reference solution and needs no model. The sample found 7 passing oracles and 3 failures, a 30% defect rate that extrapolates to roughly 16 broken tasks among the 54; 44 remain unswept. The three failures are three different defect classes rather than one bug repeated: black-ink never ships its /app/operations.log input, because the root .gitignore *.log rule swallowed the fixture and it is now lost from the working tree too; amber-quarry's oracle runs but the verifier rejects all six hidden cases as malformed; amber-dial's reference solution is correct but exceeds the verifier's hardcoded 180s deliverable budget (rc=124). None is fixable without a decision: restoring black-ink means authoring benchmark content, amber-quarry needs a ruling on whether the fixtures or the verifier is wrong, and raising amber-dial's timeout makes the task easier. See never_passed.json and oracle_defects.json."
)

for s in "${SPECS[@]}"; do ARGS+=(--job "$s"); done

if [ "${1:-}" = "--no-upload" ]; then ARGS+=(--no-upload); fi

echo "publishing v3.3 from ${#SPECS[@]} jobs"
exec bash "$EVAL/tools/publish_version.sh" "${ARGS[@]}"
