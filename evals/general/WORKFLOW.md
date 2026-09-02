# General Eval — Build & Verification Workflow

767 Harbor tasks for training and evaluating coding agents. Covers the full
Terminal-Bench 2.1 competency space (726 atomic competencies, 725 covered,
1 waived as environmentally infeasible) plus 271 supplementary general-coding
tasks. Zero contamination with Terminal-Bench 2.1 — verified by byte-level
audit.

## Dataset composition

| Source | Tasks | Description |
|---|---|---|
| v2/v3 clean-room | 496 | Authored to cover tb2.1 competencies without containing any tb2.1 content |
| v1 filtered | 271 | General coding tasks (Nemotron/TMax seeds); filtered for verifier quality |
| **Total** | **767** | |

v1 filtering removed 245 tasks with weak verifiers (no deliverable execution)
and 8 tasks with tb2.1 contamination (block/n-gram overlap). The v1 family is
supplementary: it claims no tb2.1 competencies and is exempt from the
clean-room contract lint and competency-claim gates by design (same exemption
`check_tb21_coverage.py` applies).

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
tb2.1 content (the first 494 in fleet waves; cedar-summit and flint-gate
added 2026-09-02 to close the last feasible gaps). Each task:

- Has a self-contained instruction with exact paths, formats, edge cases
- Uses an approved base image (`bench-base:*`) or documented CA-patched image
- Has an objective verifier that writes `/logs/verifier/reward.txt` (1.0 or 0.0)
- Executes the agent's deliverable on hidden generalization cases
- Has an oracle solution that passes from a pristine container
- Uses opaque two-word IDs (not derived from tb2.1 ordering)

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
| Layout & contract lint | `tools/lint_tasks.py` | 496 clean-room tasks, 0 problems (271 legacy v1 skipped by design) |
| Competency coverage | `tools/check_tb21_coverage.py` | 725/726 covered, 1 waived-infeasible, 0 errors |
| Difficulty calibration | `tools/check_difficulty.py` | 0 problems (--allow-unmeasured) |
| Provenance | `tools/update_provenance.py` + `check_reproducibility.py` | 12,128 files, 0 drift |
| Independence audit | `tools/audit_independence_stream.py` | **Clean**: 13,237 payloads, exact=0, block=0, ngram=0, canary=0, repo=0 |
| Similarity triage | `tools/check_task_similarity.py` | 14 flagged pairs, all cleared by two-reviewer blind triage (boilerplate/API-signature overlaps; no direct recipes) |
| Suite report | `tools/suite_report.py` | **SUITE PASS** |

### Independence audit detail

The audit scans every file in the tree (instructions, Dockerfiles, tests,
solutions, fixtures, nested archive members) against the frozen tb2.1
reference checkout and requires zero overlap:

- **Exact matches**: SHA-256 file identity (0 found)
- **Block matches**: Fixed-size block overlap at 32/64/256/1024 bytes (0 found)
- **N-gram matches**: Long text n-gram overlap after line-ending normalization (0 found)
- **Canary matches**: Known benchmark canary strings (0 found)
- **Source repository matches**: Shared upstream repos with tb2.1 (0 found)

The audit never silently skips files. Exclusions are path+hash-based,
documented in the tool source, and narrowly scoped (e.g., x264 encoder
signature in self-authored video fixtures, Node.js LICENSE files in official
distributions). Exclusion matching resolves labels relative to the suite
ROOT, so it survives directory renames.

## 2026-09-02 addition — closing the last feasible coverage gaps

Two tasks were authored for the three remaining uncovered competencies
(the fourth, C-c65bea8a kernel rebuild + QEMU/KVM boot, is environmentally
infeasible on Docker-on-macOS and carries a documented waiver in
`private-audit/infeasible/kernel-rebuild.json`):

- **cedar-summit** (C-6f29d769): multi-service interactive negotiation.
  Four Flask microservices (coordinator desk + three colleague phones),
  interactive bash dialers that POST each typed line to the services, an
  authentication phrase issued by the coordinator and required by every
  phone (wrong/stale phrase hangs up with no data), and a unique optimal
  offsite plan derived from hidden availability/preference/constraint
  state. Verifier executes the plan against the booking desk, checks it
  against the hidden optimum, and proves the authenticated conversations
  happened via the services' call journal.
- **flint-gate** (C-2e082c47 + C-c34cf87e): an optionally gated LayerNorm
  as a single `@triton.jit` kernel under `TRITON_INTERPRET=1`. Hidden
  battery of shapes in both gate and no-gate modes (B=1, S=1, D=1, odd
  non-power-of-two D) at rtol=1e-4/atol=1e-6, plus static inspection that
  fails on any `tl.sum`/`.sum(`/built-in `sum` or torch/numpy/math inside
  kernel bodies — reductions must be explicit `tl` ops.

Also completed the two in-flight tasks **kiln-anchor** and **larch-vane**
(their verifiers required `tests/hidden` fixtures that had never been
committed; fixtures added, oracles re-verified). All four oracles pass
reward=1.0 from pristine containers (`specs/oracle_report.json`).

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
