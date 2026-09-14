# v4.3c consolidation — remaining steps

Operational checklist. Written while three jobs were still running so the plan
survives a context compaction. Update the checkboxes as steps land.

## Status: steps 1-7 DONE, committed as 3ded0b3a

Wave 3 landed and was committed on 2026-09-14. 106 tasks registered, all seven
gates exit 0, census 106/106 with oracle reward 1 and nop reward 0, zero
instruction leaks, disjointness problems=0. Suite is now 1075 tasks total and 805
rubric-graded.

Still outstanding:

- **Step 6, the contamination audit, was still running when the commit was made.**
  It had finished the block phase over 18420 payloads and was in the n-gram
  phases, which are the expensive ones. Its findings must be acted on. If it names
  a wave-3 task, fix that task and commit the fix; do not treat the commit as
  closing this item.
- **Step 8, the ten deferred image-size fixes.**
- **Step 7 for the fix-up wave**, which is a separate commit from wave 3 and was
  deliberately kept out of 3ded0b3a.

State when written: census 59/102 recorded, all passing. Wave 3 at 211/213 agents
with 2 reviews in flight. Image-size fix-up at 8/26.

## 1. Wait for both workflows to reach status=completed

    workflow_control status v43c-leftover-pool-mtymggjf-312ijt
    workflow_control status v43-image-size-fixup-mu0n7fk3-cwt4ml

Do not start step 2 until the wave-3 run is `completed`. Registering or auditing
while reviewers are still editing means measuring a moving tree.

## 2. Re-census the six at-risk tasks in a FRESH output dir

The main census defaults to excluding tasks under review, but the in-flight set
moved while it ran. These six were either excluded while under review, or queued
while under review and so may have been measured mid-edit:

    companion-berm companion-flint crance-bell crojack-wheel
    berm-coaming cringle-barquentine

`RESUME=0` and a separate `OUT` are both required. Resume skips any task already
recorded `rc=0`, so a stale pass earned while a reviewer was still editing the
task would otherwise be kept forever and never re-measured.

    OUT=/tmp/v43c-census-final SHARDS=3 RESUME=0 \
      ONLY=companion-berm,companion-flint,crance-bell,crojack-wheel,berm-coaming,cringle-barquentine \
      bash runs/census-v43c.sh

Then confirm all six report oracle reward 1.0 and nop reward 0.0 in
`/tmp/v43c-census-final/`. Any failure must be fixed before registration, not
registered and waived.

`futtock-careen` was never authored and is not censused or registered. It should
be recorded as an abandoned slot.

## 3. Register the wave

    python3 tools/register_task_wave.py --slots specs/v43c_slots.json \
        --wave "v4.3c real-issue wave" --dry-run
    python3 tools/register_task_wave.py --slots specs/v43c_slots.json \
        --wave "v4.3c real-issue wave"

Additive only: it aborts if any pre-existing `difficulty.json` or
`coverage_claims.json` entry changes. Expect 106 added, `futtock-careen`
rejected as incomplete. Dry run projected 1 easy / 101 medium / 4 hard, taking the
suite to easy 108 / medium 438 / hard 259.

Do NOT run `tools/build_difficulty.py`. It recomputes every task from its own
task-level difficulty.json and flips 208 pre-existing buckets.

## 4. Derived specs

    python3 tools/build_coverage.py
    python3 tools/update_provenance.py
    python3 tools/check_reproducibility.py
    python3 tools/build_skill_inventory.py

`update_provenance.py` must run after the tree stops moving, which is why it was
deliberately not run during the concurrent waves.

## 5. Gates

    python3 tools/lint_tasks.py
    python3 tools/check_difficulty.py --allow-unmeasured
    python3 tools/check_upstream_disjointness.py
    python3 tools/check_task_files_tracked.py
    python3 tools/check_image_size_hygiene.py
    python3 tools/check_reproducibility.py

`check_difficulty.py` without `--allow-unmeasured` exits 1 on 423 pre-existing
"oracle time not measured" errors. That is a pre-existing condition of the
committed suite, not something this wave introduces.

`check_task_files_tracked.py` will fail until step 7 stages the new task
directories. That is expected at this point in the sequence.

## 6. Frozen-tree contamination audit

Only now, with the tree static:

    python3 tools/audit_independence_stream.py --skip-verified-assets \
        --reference-root /home/ee/tb-ref/terminal-bench \
        --reference-provenance specs/tb21_source_repositories.json

## 7. Commit — stage paths explicitly

    git add evals/general/specs/ evals/general/reports/
    git add evals/general/tasks/<each new task>

Never `git add evals/general/tasks` wholesale while other work is uncommitted; it
sweeps in whatever else is in the tree. Check `git status` first and confirm the
staged set is exactly the wave.

For the image-size fix-up, stage only `environment/Dockerfile` (and `task.toml`
where a fix genuinely required it) for the 26 touched tasks, plus
`reports/v43_image_size_fixup.md`. Verify no `tests/` change landed: a size fix
has no business touching a verifier.

## 8. Deferred image-size fixes

Ten flagged tasks were excluded from the fix-up wave because reviewers owned their
directories. Run them after step 7:

    alewife-anchorage alewife-dune corvette-towpath cutwater-swell
    kelson-current pintle-berm ropewalk-passage sennit-foresheet
    strake-offing waterway-wharf

Note that five of these — `alewife-anchorage`, `alewife-dune`,
`corvette-towpath`, `cutwater-swell` and others in the census list — have already
been censused and passed at their current image size. Shrinking them afterwards
requires re-running the both-directions gate on each, since the whole point of the
fix is that it must not change behaviour and only a re-run proves that.

## 9. Independent verification before trusting any of it

Subagent output is untrusted by policy. Before committing:

- Rebuild a sample of the fix-up wave's images and confirm the reported unique
  sizes with `docker system df -v`, not `docker images` (which reports total
  including shared layers).
- Parse oracle/nop rewards from raw per-task harbor logs, never from a summary
  line.
- `git diff` every touched `tests/` directory against HEAD.
- Three earlier censuses each caught a task that had already passed its author
  and its independent reviewer.
