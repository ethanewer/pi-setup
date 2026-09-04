# General Eval — Build & Verification Workflow

786 Harbor tasks for training and evaluating coding agents. Covers the full
Terminal-Bench 2.1 competency space (726 atomic competencies, 723 covered,
1 waived as environmentally infeasible, 2 currently uncovered following the
removal of two broken tasks in v3.1) plus 271 supplementary general-coding
tasks (v1 family) and 21 supplementary clean-room skill-coverage tasks.
Zero contamination with Terminal-Bench 2.1 — verified by byte-level audit.

## Dataset composition

| Source | Tasks | Description |
|---|---|---|
| v2/v3 clean-room | 496 | Authored to cover tb2.1 competencies without containing any tb2.1 content |
| v1 filtered | 271 | General coding tasks (Nemotron/TMax seeds); filtered for verifier quality |
| Supplementary skill tasks | 21 | Clean-room tasks exercising skill domains not covered by the rest of the suite (see the 2026-09-02 additions below) |
| **Total** | **786** | Two further skill tasks (cinder-hearth, drift-canyon) were removed in v3.1: unbuildable image and missing hidden fixtures respectively |

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
| Layout & contract lint | `tools/lint_tasks.py` | 515 clean-room tasks, 0 problems (271 legacy v1 skipped by design) |
| Competency coverage | `tools/check_tb21_coverage.py` | 723/726 covered, 1 waived-infeasible, 2 uncovered after v3.1 removals |
| Difficulty calibration | `tools/check_difficulty.py` | mirrors coverage gate (--allow-unmeasured) |
| Provenance | `tools/update_provenance.py` + `check_reproducibility.py` | ~12,500 files, 0 drift |
| Independence audit | `tools/audit_independence_stream.py` | **Clean**: exact=0, block=0, ngram=0, canary=0, repo=0 |
| Similarity triage | `tools/check_task_similarity.py` | flagged pairs cleared by two-reviewer blind triage (boilerplate/API-signature overlaps; no direct recipes) |
| Suite report | `tools/suite_report.py` | see `private-audit/reports/suite_report.json` |

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
infeasible on Docker-on-macOS and carries a documented waiver in
`private-audit/infeasible/kernel-rebuild.json`):

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
  kernel bodies — reductions must be explicit `tl` ops.

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

## Model benchmarks

Original v2 suite (204 tasks) on `openrouter/z-ai/glm-5.3-flash`:

| Agent | Score |
|---|---|
| claude-code | 146/204 = 0.716 |
| terminus-2 | 141/204 = 0.691 |
| pi (PAgent) | 136/204 = 0.667 |

Full results archived in HF dataset `eewer/general-agent-bench-results`.

## Large assets

Five fixture binaries (>20MB) are gitignored. Fetch from HF `v2/assets/` or
upstream per `specs/large_assets.json` (SHA-256 verified):

- `hadoop-3.3.6.tar.gz` (prism-bridge)
- `node-v20.19.3-linux-x64.tar.xz` (harbor-gasket)
- `vosk_model.zip` (zephyr-orchid)
- `Gr.fst`, `HCLr.fst` (raven-orchid)
