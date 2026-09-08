#!/usr/bin/env bash
# Publish v3.4 using the committed tools/publish_version.sh wrapper.
#
# v3.4 carries the v3.3 tree forward and replaces every record for the 28 tasks
# whose definitions, fixtures or environments were repaired. A full-suite oracle
# census -- all 787 tasks through their own reference solution -- found 24 tasks
# whose oracle could not pass, and repairing those plus 6 more found on the way
# gives 28. All six pairs are re-run for each, 168 trials, because re-running only
# the failures would re-roll the dice for losses and never for wins.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
JOBS=/home/ee/general-eval-runs/jobs
# publish_version.sh needs HF_TOKEN in the environment for the upload step.
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }
GLM_PATH="z-ai/glm-5.3-flash"
DSK_PATH="deepseek/deepseek-v4-flash-0731"
GLM_META="openrouter/z-ai/glm-5.3-flash"
DSK_META="openrouter/deepseek/deepseek-v4-flash-0731"

# job-name:harness:model-in-path:model-in-metadata
# The path component is the bare provider/model slug for every pair, matching the
# v3.3 tree layout. The metadata component carries harbor's -m string verbatim,
# which is openrouter-prefixed for pi and terminus-2 but bare for claude-code
# because that agent passes the whole -m string through as ANTHROPIC_MODEL.
SPECS=(
  "v34-pi-glm:pi:$GLM_PATH:$GLM_META"
  "v34-pi-dsk:pi:$DSK_PATH:$DSK_META"
  "v34-t2-glm:terminus-2:$GLM_PATH:$GLM_META"
  "v34-t2-dsk:terminus-2:$DSK_PATH:$DSK_META"
  "v34-claude-glm:claude-code:$GLM_PATH:$GLM_PATH"
  "v34-claude-dsk:claude-code:$DSK_PATH:$DSK_PATH"
  # Two terminus-2/glm trials died on harbor's tmux integration under the load of
  # six jobs running thirty concurrent trials, and were re-run in their own job.
  # This entry was missing from the first v3.4 publish, so cobalt-quill and
  # tundra-orchid for that pair silently fell back to their stale v3.3 mirror
  # records -- one of which published a 0 where the re-run had earned a 1. Listed
  # last so it overrides the job holding the flaked trials.
  "v34-t2-glm-retry:terminus-2:$GLM_PATH:$GLM_META"
)

ARGS=(--version v3.4
      --mirror /tmp/hf-upload/v3.3
      --out /tmp/hf-upload/v3.4
      --jobs-dir "$JOBS"
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --note "v3.4 = the v3.3 tree with 28 broken tasks repaired, 2 tasks retired, and every record for the repaired tasks re-run across all six harness/model pairs. THE SUITE IS NOW 785 TASKS, not 787, so pass counts are not directly comparable with v3.3 and earlier; rates over 785 are. No reward is fractional and no record is unscoreable."
      --note "slate-fjord and v1-item-043-hard were retired and are recorded in specs/retired_tasks.json. Both were removed because their own reference solution cannot pass, so every record for them measured a defect rather than agent capability. slate-fjord cannot run in this harness at all: it needs a loopback SSH daemon started at container start, the harness does not execute the image ENTRYPOINT in the trial container, and under network_mode none the loopback port is unreachable with no way to bring it up. It scored 0 for all six pairs in v3.2 and v3.3. v1-item-043-hard fails its own MCMC convergence gates on n_eff and divergences; two pairs scored 1.0 and four scored 0, and those twelve records are dropped rather than kept because a task whose reference solution cannot meet its own stated convergence criteria has no defensible pass bar. Competency coverage is unchanged at 725/726: C-a9d4f82b was covered by both slate-fjord and umber-yonder, and v1-item-043-hard carried no competency tag."
      --note "A full-suite oracle census ran every task through its own reference solution, one trial each, no model and no inference. Before the repairs 763 of 787 passed and 24 failed. After the repairs and the two retirements the census was run again over all 785; both censuses ship as v34_census_before.json and v34_census_after.json. A task whose own solution cannot earn reward 1 is broken no matter what any agent scored, so this is a census rather than a sample: sampling the never-passed tasks alone found 14 defects in 54 and would have missed moss-loft and umber-vault, which some pairs had already passed."
      --note "The largest single defect was environmental and affected 162 tasks. [environment] cpus is enforced by Docker as a CFS quota, not a CPU-affinity mask, so the process still sees all 64 host cores and every thread pool sized from the core count oversubscribed the quota. Measured in amber-dial's own image with its own reference solution, 320 training steps took 519.8s against 1.6s once pinned: a 325x penalty straight through the verifier's 180s budget. brine-mesa requires its OpenMP build to beat its serial build and 64 threads on a 4-CPU quota made parallel 5.6x slower, so the required speedup was unreachable. tools/pin_numeric_threads.py now pins OMP/MKL/OpenBLAS/numexpr to the declared cpus for all 162 and gates on it. Pinning only removes oversubscription and cannot change a computed result."
      --note "Ten tasks lost fixtures to the repository-root .gitignore *.log rule: any fixture directory whose contents were all .log files was never committed and is unrecoverable. black-ink, meadow-yonder, tundra-orchid, drift-mantle, willow-upland, juniper-yonder, vine-yonder, umber-summit, zephyr-notch and amber-quarry all shipped without inputs their own verifier and instruction require. Where the verifier derives its expectation from the fixture at run time the reconstruction only has to satisfy the documented contract; where a sha or count was pinned the file was rebuilt to reproduce that pin and verified against the task's own reference implementation."
      --note "Git cannot represent an empty directory or a mode other than 100644/100755, and both bit this suite. amber-quarry's hidden/empty/logs and vine-helix's hidden/fix/f3/work were meant to be empty and did not exist. umber-mantle's credentials.file has to be 0600 because its exclusion rule keys on the missing other-read bit, so checked out world-readable the rule could never fire and the task was unsolvable; it is now chmod-ed at build time and on each staged hidden tree. All four of kite-helix's release_alias symlinks were committed as regular files holding their target's bytes, so no tar could ever contain a symlink member."
      --note "Seven reference solutions were wrong. copper-vane read a SQLite record as decode(...)[:4] although id is a rowid alias stored as NULL in the payload, shifting every column left and putting a date in the REAL mass field; all five expected.json files had been generated through the same bug and were regenerated from the corrected decoder. cobalt-quill's tokenizer never NUL-terminated a token so parse_hex32 rejected every pair in every fixture. nectar-helix's resharder capped items inside each shard but never at the root, which also holds manifest.tsv. kite-summit rounded the footprint ceiling up where the instruction and grader both round to nearest. kelp-notch read a fixed second column and aborted on a padded three-column line. tern-delta preferred /usr/bin/python3, a different interpreter from the one pip installed numpy into. vine-helix shipped no jobs/ workloads at all though its instruction lists four."
      --note "Six verifiers or fixtures were wrong rather than the solutions. amber-quarry carried a second task's ONNX-mirroring material wholesale, which is what made all six of its hidden cases report malformed. harbor-notch's edge-terms expected last-wins where the instruction says to sum and every sibling fixture does sum. umbral-mesh pinned a telemetry sha that did not match the shipped file the expectations were built from. tundra-orchid sent its diagnostics to /dev/null so a missing fixture and a wrong answer were indistinguishable. slate-fjord's sshd_config check matched Debian's commented-out defaults and so passed an unprovisioned server. birch-bight shipped in v3.3 with an EXIT trap reading 'finalize_reward; ; [ -f ... ]', a bash syntax error that bash -n cannot see because a trap body is a string until the trap fires; ensure_reward_guard now normalises, repairs and validates every trap body as a gate."
      --note "Two tasks could not be repaired and were retired rather than left in the suite. slate-fjord needs a loopback SSH daemon started at container start; the harness does not execute the image ENTRYPOINT in the trial container (reproduced twice with the oracle printing a preflight showing sshd absent, sshd_config still stock Debian and ports 22 and 2222 dead, while the /srv/git fixtures built at image time were present), and under network_mode none the loopback port is dead even with sshd running, with no way to bring it up because ip is not installed and the container has no NET_ADMIN. Its oracle now prints that preflight instead of dying silently at a git -q invocation, and its sshd_config anti-tamper check no longer matches Debian's commented-out defaults, but neither makes the task runnable here. v1-item-043-hard's oracle still fails its own MCMC convergence gates; fixing it means tuning the sampler and re-validating across repeated one-to-two-hour oracle runs, which is re-authoring rather than repair."
      --note "Both conventions for agent timeouts remain published per pair, as they have been since v3.3: the leaderboard is verifier-authoritative, and results.json also carries the strict variant where any trial with agent_timeout counts 0. The choice reorders the table, so it is stated rather than left implicit."
      --note "168 records were re-run, six pairs across the 28 repaired tasks, plus two terminus-2/glm trials re-run a second time after harbor's tmux integration dropped the session mid-rollout under 30 concurrent trials. Those two died with RuntimeError rather than an agent timeout, so collect_task_records.py refused to score them 0 and demanded a re-run; both earned reward 1 on retry, and the flaked trial dirs are preserved under general-eval-runs/failed-attempts with a README explaining why they are not in the published tree."
)

echo "=== [$(date -Is)] publishing v3.4 ==="
printf '  %s\n' "${SPECS[@]}"
# Every repaired task has to arrive from a fresh trial for every pair. Its old
# records are scoreable, so a gap here is invisible to the completeness and
# binarity gates: the mirror's pre-repair record just carries forward.
REQUIRE=()
while read -r T; do
  [ -n "$T" ] && REQUIRE+=(--require-rerun "$T")
done < /tmp/v34_rerun_tasks.txt
echo "  requiring fresh records for $(wc -l < /tmp/v34_rerun_tasks.txt) repaired tasks x 6 pairs"
"$EVAL/tools/publish_version.sh" "${ARGS[@]}" "${REQUIRE[@]}" \
  $(for s in "${SPECS[@]}"; do printf -- '--job %q ' "$s"; done)
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc
