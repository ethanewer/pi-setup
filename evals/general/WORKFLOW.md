# General Eval — Build & Verification Workflow

785 Harbor tasks for training and evaluating coding agents. Covers the full
Terminal-Bench 2.1 competency space (726 atomic competencies, 725 covered,
1 waived as environmentally infeasible, 0 uncovered) plus 270 supplementary
general-coding tasks (v1 family) and 20 supplementary clean-room skill-coverage
tasks. Zero contamination with Terminal-Bench 2.1, verified by byte-level audit.

Every verifier writes a binary reward: `/logs/verifier/reward.txt` contains
exactly `1` or `0`. `tools/check_binary_reward.py` proves this statically for
all 785 tasks and runs in the gate pipeline, so partial credit cannot come back.

## Dataset composition

| Source | Tasks | Description |
|---|---|---|
| v2/v3 clean-room | 495 | Authored to cover tb2.1 competencies without containing any tb2.1 content |
| v1 filtered | 270 | General coding tasks (Nemotron/TMax seeds); filtered for verifier quality |
| Supplementary skill tasks | 20 | Clean-room tasks exercising skill domains not covered by the rest of the suite (see the 2026-09-02 additions below) |
| **Total** | **785** | 21 skill tasks were authored; cinder-hearth was removed in v3.1 (unbuildable image behind a network proxy). drift-canyon was removed at the same time for a lost hidden fixture, then restored in v3.1 once the fixture was recreated, so it is counted here. slate-fjord and v1-item-043-hard were removed in v3.4 and are recorded in `specs/retired_tasks.json` |

### Tasks retired in v3.4

Both were removed because their own reference solution cannot pass, so every
record for them measured a defect rather than agent capability. Removals are
tracked in `specs/retired_tasks.json`, which `tools/assemble_publish.py` reads so
that carrying an older mirror forward drops their records instead of failing on
rows that are no longer in the suite.

- **slate-fjord** could not run in this harness at all. It needs a loopback SSH
  daemon started at container start, the harness does not execute the image
  `ENTRYPOINT` in the trial container, and under `network_mode: none` the loopback
  port is unreachable with no way to bring it up. It scored 0 for all six pairs in
  v3.2 and v3.3. Its competency `C-a9d4f82b` remains covered by umber-yonder, so
  the competency count is unchanged.
- **v1-item-043-hard** fails its own MCMC convergence gates on `n_eff` and
  divergences. Two pairs scored 1.0 and four scored 0, so unlike slate-fjord it did
  produce discriminating records; they are dropped rather than kept because a task
  whose reference solution cannot meet its stated convergence criteria has no
  defensible pass bar. It carries no `C-` competency tag.

Removing tasks changes the suite denominator, so pass counts from v3.4 onward are
not directly comparable with v3.3 and earlier. Rates over 785 are.

v1 filtering removed 245 tasks with weak verifiers (no deliverable execution)
and 8 tasks with tb2.1 contamination (block/n-gram overlap). The v1 family is
supplementary: it claims no tb2.1 competencies and is exempt from the
clean-room contract lint and competency-claim gates by design. The 21
supplementary skill tasks likewise claim no tb2.1 competencies (recorded
with an explicit `claims_no_competencies` flag in
`specs/coverage_claims.json`), but unlike v1 they satisfy the full
clean-room contract lint.

## How it was built

### 1. Reference freeze

Terminal-Bench 2.1 pinned at commit `1a6ffa96` of
`laude-institute/terminal-bench`. The merkle hash of the task checkout is
recorded in `specs/frozen_reference.json`. `tools/freeze_reference.py --verify`
fails closed if the checkout drifts.

### 2. Competency inventory

241 tb2.1 tasks were analyzed to extract 955 raw findings, normalized to 726
atomic competencies (`specs/tb21_competencies.json`). Each competency has an
opaque ID, a neutral definition, a failure mode, and required artifacts. The
mapping to reference evidence is in `private-audit/competency_map.json`
(gitignored — contains reference path names, not reference content).

### 3. Clean-room task authoring (v2 tasks)

496 tasks were authored to exercise the 726 competencies without copying any
tb2.1 content (the first 494 in fleet waves; amber-engine and marble-ridge
added 2026-09-02 to close the last feasible gaps). Each task:

- Has a self-contained instruction with exact paths, formats, edge cases
- Uses an approved base image (`bench-base:*`) or documented CA-patched image
- Has an objective verifier that writes `/logs/verifier/reward.txt` (1.0 or 0.0)
- Executes the agent's deliverable on hidden generalization cases
- Has an oracle solution that passes from a pristine container
- Uses opaque two-word IDs (not derived from any external ordering)

Tasks were authored in waves by LLM agents (deepseek-v4-flash, glm-5.3-flash)
with the constraint that the authoring model had no access to tb2.1 content.
6 tasks were later found to have byte-level overlap with tb2.1 vendored
archives (shared upstream sources like CRAN packages) and were removed.

### 4. Verifier quality filtering (v1 tasks)

271 of 524 v1 general-coding tasks were retained. The filter requires the
verifier to execute the agent's deliverable (not just check file existence)
and to perform dynamic checks (not just compare against a fixed expected
output). 245 tasks with weak verifiers were removed.

### 5. Contamination removal

8 v1 tasks were removed after the independence audit found block/n-gram
overlap with tb2.1 content (e.g., shared R package tarballs, C source files).
All had redundant coverage, so removal cost zero competency coverage.

## Verification gates

All gates run via `tools/rebuild_and_audit.sh` or individually:

| Gate | Tool | Result |
|---|---|---|
| Reward binarity | `tools/check_binary_reward.py` | 785/785 provably binary, 0 problems |
| Reward binarity self-test | `tools/selftest_binary_reward.py` | 23/23 fixtures (12 fractional shapes flagged, 11 binary shapes passed) |
| Reward on every exit path | `tools/ensure_reward_guard.py` | 785/785 guarded, 0 unpatchable; also parses every EXIT trap body, which `bash -n` on the file cannot do |
| Thread pools vs CPU quota | `tools/pin_numeric_threads.py` | 161/161 pinned to their declared `cpus`, 0 skipped |
| Git repos safe for any user | `tools/ensure_git_safe_directory.py` | 8/8 images that build a repository set a system-wide `safe.directory`, 0 skipped |
| Layout & contract lint | `tools/lint_tasks.py` | 516 clean-room tasks, 0 problems (271 legacy v1 skipped by design) |
| Competency coverage | `tools/check_tb21_coverage.py` | 725/726 covered, 1 waived-infeasible, 0 problems |
| Difficulty calibration | `tools/check_difficulty.py` | 516 measured (49 easy / 251 medium / 216 hard), 0 problems; the 271 v1 tasks carry no rubric, hence `--allow-unmeasured` |
| Provenance | `tools/update_provenance.py` + `check_reproducibility.py` | 12,495 files, 0 drift |
| General inventory | `tools/check_general_coverage.py` | not-retained (decision D1), 0 errors |
| Independence audit | `tools/audit_independence_stream.py` | **Clean**: exact=0, block=0, ngram=0, canary=0, repo=0 |
| Similarity triage | `tools/check_task_similarity.py` | flagged pairs cleared by two-reviewer blind triage (boilerplate/API-signature overlaps; no direct recipes) |
| Suite report | `tools/suite_report.py` | see `private-audit/reports/suite_report.json` |

The independence audit, similarity triage, reference freeze and suite report all
need the frozen tb2.1 checkout named in `specs/frozen_reference.json`. They
cannot run on a clone that does not have it; pass the path as
`bash tools/rebuild_and_audit.sh /path/to/original-tasks`.

### Reward binarity

The contract is that `reward.txt` is `1` or `0`. It was documented but never
enforced, so 45 verifiers shipped partial credit: 41 `v1-item-*`, 3 `v1-skill-*`
and one clean-room task (`zephyr-bridge`, a weighted 0.5 visible + 0.25 per
hidden case accumulator). `v1-item-035-main` could even write `1.25`.

`tools/check_binary_reward.py` proves binarity statically rather than by
pattern-matching for suspicious arithmetic. Per task it builds the reward value
cone: the expressions written to `reward.txt`, every assignment to a variable
that reaches it, and the stdout of any command substitution or heredoc whose
output is captured into it. Shell and embedded python are audited as separate
scopes, because a heredoc computing `reward = passes / total` for python has
nothing to do with the shell variable that captures that interpreter's stdout.
A helper run only for its exit code contributes nothing, so its `%.4f`
diagnostics are not mistaken for fractional rewards.

All 45 were fixed by binarizing at full credit: the reward is now `1` exactly
where the old scoring produced `1.0` or more, and `0` everywhere else. Graded
ladders had their partial tiers set to `0`; computed fractions are wrapped at
the write, so the internal computation and its diagnostics survive. The pass
set is unchanged, which is what makes already-published records rescorable
without re-running any model.

### Independence audit detail

The audit scans every file in the tree (instructions, Dockerfiles, tests,
solutions, fixtures, nested archive members) against the frozen tb2.1
reference checkout and requires zero overlap:

- **Exact matches**: SHA-256 file identity (0 found)
- **Block matches**: fixed-size block overlap at 32/64/256/1024 bytes (0 found)
- **N-gram matches**: long text n-gram overlap after line-ending normalization (0 found)
- **Canary matches**: known benchmark canary strings (0 found)
- **Source repository matches**: shared upstream repos with tb2.1 (0 found)

The audit never silently skips files. Exclusions are path+hash-based,
documented in the tool source, and narrowly scoped (e.g., x264 encoder
signature in self-authored video fixtures). Exclusion matching resolves
labels relative to the suite ROOT, so it survives directory renames.

## 2026-09-02 addition — closing the last feasible coverage gaps

Two tasks were authored for the three remaining uncovered competencies
(the fourth, C-c65bea8a kernel rebuild + QEMU/KVM boot, is environmentally
infeasible and carries a permanent waiver in the tracked
`specs/infeasible_waivers.json`):

- **amber-engine** (C-6f29d769): multi-service interactive negotiation.
  Four Flask microservices (coordinator desk + three colleague phones),
  interactive bash dialers that POST each typed line to the services, an
  authentication phrase issued by the coordinator and required by every
  phone (wrong/stale phrase hangs up with no data), and a unique optimal
  offsite plan derived from hidden availability/preference/constraint
  state. Verifier executes the plan against the booking desk, checks it
  against the hidden optimum, and proves the authenticated conversations
  happened via the services' call journal.
- **marble-ridge** (C-2e082c47 + C-c34cf87e): an optionally gated LayerNorm
  as a single `@triton.jit` kernel under `TRITON_INTERPRET=1`. Hidden
  battery of shapes in both gate and no-gate modes (B=1, S=1, D=1, odd
  non-power-of-two D) at rtol=1e-4/atol=1e-6, plus static inspection that
  fails on any `tl.sum`/`.sum(`/built-in `sum` or torch/numpy/math inside
  kernel bodies, since reductions must be explicit `tl` ops.

Also completed the two in-flight tasks **kiln-anchor** and **larch-vane**
(their verifiers required `tests/hidden` fixtures that had never been
committed; fixtures added, oracles re-verified). All four oracles pass
reward=1.0 from pristine containers (`specs/oracle_report.json`).

## 2026-09-02 addition — supplementary skill-coverage tasks

Twenty-one clean-room tasks were added to exercise skill domains that the rest
of the suite does not cover. Each was authored from a neutral skill
description only, then independently re-verified by a second agent (fresh
docker builds, oracle reward=1; several genuine instruction/verifier
mismatches were found and fixed in that phase), and every oracle was re-run
through harbor's oracle agent.

Seven domain-coverage tasks:

| Task | Domain | Skill exercised |
|---|---|---|
| `frost-link` | Hardware / CAD | parametric spacer/flange geometry engine (centers, clearances, area, volume, mass, design-rule validation) |
| `marrow-vault` | Hardware / RTL | synchronous FIFO in Verilog; three hidden golden-model testbenches under Icarus Verilog incl. parameter overrides |
| `pearl-gasket` | Media / Music | symbolic music-theory analysis: roman numerals/inversions, cadence classification, parallel P5/P8 detection |
| `meadow-mural` | Media / Design | deterministic parametric SVG layout reconstruction, structure/attribute recompute |
| `myrtle-hearth` | Science / Linguistics | ordered sound-change derivation engine (feeding/bleeding, insertion, edge conditioning) |
| `fume-wheel` | Operations / Claims | claims adjudication pipeline: deductible, coinsurance floor, per-claim and aggregate caps, reason codes |
| `pewter-meridian` | Operations / Compliance | regulatory declaration builder: validation report, threshold exemption, C-locale sorted aggregate CSV |

Fourteen further skill-gap tasks: race-condition diagnosis & repair
(`sable-journal`), bandits/online learning with delayed feedback and abrupt
drift (`sable-wharf`), NSGA-II multi-objective optimization
(`river-ferry`), conventional-commit semver/changelog tooling
(`umbral-inlet`), HMAC-signed JWT-style token lifecycle service
(`sedge-hearth`), Linux persistence-artifact scanning (`pipit-archive`),
Category-Partition test-case generation (`rust-orchid`), XXE analysis &
remediation (`raven-core`), WebSocket handshake/frame protocol server
(`velvet-terrace`), linter rule engineering (`dusk-wicket`), query-builder
window-function internals (`kelp-berth`), test-harness internals
(`glacier-basin`), HTTP client protocol internals (`amber-guest`),
helm-style manifest merge strategies (`ember-spire`).

Per policy, no upstream source repositories are vendored anywhere in the
suite — every task ships small self-authored fixture codebases.

## Oracle verification

Every task's oracle solution was run from a pristine container. The original
204-task v2 suite passed two full sweeps (204/204 ×2). Fleet-authored tasks
each passed their own oracle during authoring. A spot-check of 17
WIP-touched tasks passed 17/17 (1 fixed: brisk-kiln ctl.sh syntax bug).

The 45 verifiers binarized for the reward contract have not been oracle-swept
again; that needs harbor, which is not installed on every machine that clones
this repo. The change is safe by construction rather than by re-test: each one
now writes `1` exactly where the previous scoring produced `1.0` or more, so
the full-credit condition is untouched and only the partial tiers collapsed to
`0`. `bash -n` and a python compile of every embedded heredoc pass on all 45.
Re-run `tools/collect_oracle_results.py` over those 45 before the next publish
if you want the sweep on record.

## Model benchmarks

Six harness/model pairs over all 787 tasks, rescored under the binary reward
contract from the published v3.2 records. `unscored` counts records that shipped
with no `verifier/reward.txt` and therefore need a re-run before these numbers
are final; they are excluded from the denominator.

| Harness | Model | Pass | Scored | Rate | Unscored |
|---|---|---|---|---|---|
| pi | z-ai/glm-5.3-flash | 648 | 779 | 0.8318 | 8 |
| claude-code | z-ai/glm-5.3-flash | 646 | 785 | 0.8229 | 2 |
| claude-code | deepseek/deepseek-v4-flash-0731 | 639 | 786 | 0.8130 | 1 |
| terminus-2 | z-ai/glm-5.3-flash | 638 | 787 | 0.8107 | 0 |
| pi | deepseek/deepseek-v4-flash-0731 | 634 | 781 | 0.8118 | 6 |
| terminus-2 | deepseek/deepseek-v4-flash-0731 | 594 | 782 | 0.7596 | 5 |

Every reward is now `0` or `1`, so the pass count and the total reward are the
same number and the rate is a true pass rate. Before the fix these were means
over fractional rewards, which inflated each pair by 0.32 to 0.62 percentage
points and up to 4.90 reward points.

Historical, for continuity only: the original 204-task v2 suite on
`openrouter/z-ai/glm-5.3-flash` scored claude-code 146/204 = 0.716,
terminus-2 141/204 = 0.691, pi (PAgent) 136/204 = 0.667.

## Publishing results

Run records live in the HF dataset `eewer/general-agent-bench-results` under
`<version>/<harness>/<provider>/<model>/<task>/`, with `metadata.json`,
`trajectory.json`, `verifier/reward.txt` and `verifier/test-stdout.txt`.

- `tools/collect_task_records.py` normalizes harbor trials for one task into
  that layout, for use as an overlay. It fails closed on a missing job, a
  missing trial, or a trial with no `verifier/reward.txt`.
- `tools/rescore_binary.py` remaps fractional published rewards to binary
  (`1` iff the old value was `>= 1.0`) with no model involvement, and reports
  which records cannot be rescored because no reward was ever written.
- `tools/assemble_publish.py` carries a previous tree forward, applies
  overlays, then validates the result and writes the aggregates. It refuses to
  publish unless every pair covers every suite task, every record has all four
  files, and every reward is exactly `0` or `1`. It writes one `results.json`
  per pair plus a top-level `summary.json`, and stages the audit bundle.

The v3.2 publish predates that tooling and shows why it exists. It reported
itself complete while 22 records had no `verifier/reward.txt`, it shipped no
`results.json` for any pair, and the one aggregate it inherited from v3.1 for
claude-code/glm said `647.50` where the reward files sum to `648.50`.

When reading the dataset back, do not use the `siblings` array from
`/api/datasets/<id>`. On this repo it returns 62,787 of 68,064 files and drops
whole subtrees silently, which makes an entire harness/model pair look missing.
Walk `/api/datasets/<id>/tree/<rev>?recursive=true` and follow the `rel="next"`
link header instead.

## Large assets

Five fixture binaries (>20MB) are gitignored. Fetch from HF `v2/assets/` or
upstream per `specs/large_assets.json` (SHA-256 verified):

- `hadoop-3.3.6.tar.gz` (prism-bridge)
- `node-v20.19.3-linux-x64.tar.xz` (harbor-gasket)
- `vosk_model.zip` (zephyr-orchid)
- `Gr.fst`, `HCLr.fst` (raven-orchid)
