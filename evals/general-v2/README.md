# General Agent Benchmark v2 (general-v2)

A clean-room terminal/coding-agent benchmark built on
[Harbor](https://github.com/harbor-framework/harbor). It measures general
coding-agent ability — legacy toolchain builds, security patching, forensics,
git surgery, ML pipelines, services, emulation, and more — while being
provably free of Terminal-Bench content.

**Branch:** `general-v2-eval` · **State:** complete and verified (2026-08-29) ·
**Contract & status:** [`TODO.md`](TODO.md)

## Goals

1. **Full competency coverage.** Cover every atomic competency needed by the
   frozen Terminal-Bench 2.1 reference suite. The inventory is machine-derived
   from the 241 reference tasks (`specs/tb21_competencies.json`, 726
   competencies); v2 covers 722/726 with real verifier-backed tasks (4 are
   documented environmentally infeasible on this host).
2. **Clean room.** Contain no Terminal-Bench task names, prompts, fixtures,
   solutions, hidden tests, source trees, or byte-level artifacts, and give no
   model a direct recipe for a reference task. Enforced by a byte-level
   independence audit (exact hashes, archive members, fixed-size blocks,
   long n-grams, canary strings) plus a source-provenance comparison and a
   two-person blind similarity review — all clean on the frozen tree.
3. **Full difficulty range.** Span easy focused probes to hard deep/
   adversarial/quantitative tasks (currently 2 easy / 84 medium / 118 hard),
   each scored on a documented 10-dimension rubric with difficulty floors per
   competency.
4. **Deterministic, objective, independently verified tasks.** Every task has a
   pristine deterministic environment, an objective verifier that always writes
   `/logs/verifier/reward.txt`, an oracle that passes from a pristine
   container, and hidden generalization cases so visible answers cannot be
   hard-coded. Two full oracle sweeps must reproduce identically (they do).
5. **Honest grading.** Every recorded grade must reflect model capability. A
   408-trial forensic audit found 0 false positives; 28 verifier/instruction
   contract defects were found, repaired, and the affected trials re-run.

## Current suite

- **204 tasks** in `tasks/` (opaque two-word IDs, not reference-ordered):
  24 integrated multi-competency tasks + 180 clean-room tasks.
- Every verifier executes the requested deliverables (program/service/state),
  never merely compares a visible `answer.json`.
- `specs/`: competency inventory, task→competency coverage matrix with
  verifier evidence, difficulty rubrics, provenance (origin + SHA-256 for all
  5,074 task-owned files), frozen-reference identity.
- Benchmark results on `openrouter/z-ai/glm-5.3-flash` (204 trials each):

  | Agent | Verifier-authoritative | Strict (timeout→0) |
  |---|---|---|
  | pi (PAgent — the `p` lean profile) | **136/204 = 0.667** | 0.667 |
  | terminus-2 | **141/204 = 0.691** | 107/204 = 0.525 |

  Scoring conventions and run manifest: `private-audit/DECISIONS.md` (D3/D4)
  and `v2/results.json` in the HF dataset.

The optional General skill inventory (`evals/general/skills.json`) is NOT
retained in v2 (decision D1 in `private-audit/DECISIONS.md`): the draft's
generic probes could not prove the claimed skills. Coverage is defined solely
by the Terminal-Bench competency inventory.

## Task contract

Every task satisfies the Harbor authoring contract (full details in
`private-audit/AUTHOR_GUIDE.md`): self-contained instruction with exact paths
and edge cases, approved `bench-base:*` images, deterministic environment,
verifier that writes `/logs/verifier/reward.txt` and EXECUTES the requested
deliverables with hidden cases from `tests/hidden/`, crash-proof reward paths,
and an oracle that solves from a pristine container by doing the real work
(positive and negative controls both verified).

## Checks

```bash
# verify the frozen reference identity, rebuild derived specs, run every gate
bash tools/rebuild_and_audit.sh [REFERENCE_ROOT]

# individual gates
python3 tools/check_general_coverage.py     # "not retained" state is valid
python3 tools/check_tb21_coverage.py        # competency matrix gate
python3 tools/lint_tasks.py                 # Harbor layout + verifier contract
python3 tools/check_difficulty.py           # rubric/bucket/floor gate
python3 tools/check_reproducibility.py      # content-freeze drift check
python3 tools/check_task_similarity.py      # n-gram triage + blind review input
python3 tools/audit_independence.py         # byte/block/n-gram/canary/provenance audit
python3 tools/suite_report.py               # suite-level completion report (SUITE PASS)
```

The independence audit fails closed unless the reference checkout identity
matches `specs/frozen_reference.json`. `/frozen/terminalbench21` does not
exist on this machine (no root access); the canonical frozen root is recorded
in `specs/frozen_reference.json` and every audit resolves it from there when
`--reference-root` is omitted.

## Oracle runs

```bash
harbor run -p tasks -a oracle -y -o /tmp/general-v2-oracle --job-name general-v2-oracle
python3 tools/collect_oracle_results.py /tmp/general-v2-oracle general-v2-oracle
python3 tools/build_difficulty.py     # picks up oracle times
```

The full oracle run must produce reward 1 for every task with zero errored
trials, and a second run must reproduce it
(`python3 tools/check_reproducibility.py --compare-jobs RUN1 RUN2`).

## Model runs

```bash
python3 tools/build_runsets.py N      # symlinked runset, N samples/task (200-500 total)
PYTHONPATH=$PWD/agents harbor run -p runsets/general-v2-x1 \
  -a p_agent:PAgent -m openrouter/z-ai/glm-5.3-flash -n 20 -k 1 -y \
  -o /mnt/data/general-v2-jobs/bench-pi --job-name pi-run
harbor run -p runsets/general-v2-x1 -a terminus-2 \
  -m openrouter/z-ai/glm-5.3-flash -n 20 -k 1 -y \
  -o /mnt/data/general-v2-jobs/bench-t2 --job-name t2-run
```

## HuggingFace dataset — `eewer/general-agent-bench-results` (private)

All benchmark traces, results, audit evidence, and the gitignored large
binaries live in this dataset under `v2/`:

```
v2/pi/<task>/            final pi (PAgent) trial per task on glm-5.3-flash
v2/terminus2/<task>/     final terminus-2 trial per task on glm-5.3-flash
  agent/                 pi.txt | trajectory.json + terminus_2.pane + recording.cast
  verifier/              reward.txt, test-stdout.txt
  metadata.json          reward, timeout flag, source trial, model
  exception.txt          if the trial recorded one
v2/results.json          final tallies, scoring conventions, run manifest
v2/README.md             dataset-side documentation
v2/benchmark_report.md   suite + grading-legitimacy report
v2/audit/                independence report, suite report, forensic grading-audit
                         chunks, blind-review verdicts, coverage/difficulty/
                         provenance/inventory specs
v2/assets/               the five large binaries below (manifest.json: sha256 + sources)
v2/raw-jobs.tar.gz       every raw Harbor job directory (all runs incl. oracle sweeps)
```

Download example:

```bash
pip install huggingface_hub   # needs access to eewer/*
python3 - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download('eewer/general-agent-bench-results', repo_type='dataset',
                  allow_patterns='v2/**', local_dir='./bench-results')
PY
```

### Large binary assets

Five fixture binaries (>20MB) are gitignored in this repo and distributed via
the dataset under `v2/assets/` (sha256 + upstream sources in
`specs/large_assets.json`):

- `tasks/prism-bridge/environment/hadoop-3.3.6.tar.gz` (697MB)
- `tasks/harbor-gasket/environment/files/releases/node-v20.19.3-linux-x64.tar.xz` (25MB)
- `tasks/zephyr-orchid/environment/files/model/vosk_model.zip` (40MB)
- `tasks/raven-orchid/environment/files/vosk-model/graph/{Gr,HCLr}.fst` (45MB)

Fetch from the dataset (or upstream), verify sha256, place at the repo path —
then the corresponding task images build normally.

## Clean-room policy

No reference prompts, task names, fixtures, solutions, hidden tests, source
archives, or checkouts may enter this tree. Audit tools verify this at byte
level (exact hashes, archive members, fixed-size blocks, long n-grams, canary
strings) and at provenance level (shared source repositories). The private
audit record (`private-audit/`, gitignored) holds the competency→reference
mapping and frozen manifest; it never ships with the tasks.

## Known residuals

See `TODO.md` — "Parts NOT fully tested / known residuals" and "How to work on
the remaining items" (second-task coverage for high-risk competencies, human
inventory review, calibration panel, expert-time calibration, environment-heavy
stress testing, verifier-timeout policy, frontier-model run).
