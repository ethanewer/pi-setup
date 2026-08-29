# General Agent Benchmark v2

Clean-room coding-agent benchmark. Goal: preserve the atomic competency coverage
of the frozen Terminal-Bench reference suite without shipping any reference task
names, prompts, fixtures, source trees, solutions, hidden tests, or expected
outputs. See `TODO.md` for the completion contract.

## Status

- Reference frozen: see `specs/frozen_reference.json` (commit, checkout hash,
  timestamp; full manifest in the gitignored `private-audit/` record).
- Competency inventory: `specs/tb21_competencies.json` (opaque IDs, neutral
  descriptions). The private competency→reference mapping lives in
  `private-audit/competency_map.json` and never ships with tasks.
- Coverage: `specs/coverage.json` (task→competency matrix with verifier evidence).
- Difficulty: `specs/difficulty.json` (10-dimension rubric per task + oracle times).
- Provenance: `specs/provenance.json` (origin + SHA-256 for every task-owned file).
- The optional General skill inventory (`evals/general/skills.json`) is NOT
  retained in v2 (decision D1 in `private-audit/DECISIONS.md`): the draft's
  generic probes could not prove the claimed skills, and TODO.md permits
  removing that claim. Coverage is defined solely by the Terminal-Bench
  competency inventory.

## Task contract

Every task satisfies the Harbor authoring contract (see
`private-audit/AUTHOR_GUIDE.md`): self-contained instruction, approved
`bench-base:*` images, deterministic environment, verifier that writes
`/logs/verifier/reward.txt` and EXECUTES the requested deliverables with hidden
cases from `tests/hidden/`, and an oracle that solves from a pristine container
by doing the real work.

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
```

The independence audit fails closed unless the reference checkout identity
matches `specs/frozen_reference.json`. `/frozen/terminalbench21` does not exist
on this machine (no root access); the canonical frozen root is recorded in
`specs/frozen_reference.json` and every audit resolves it from there when
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

## Clean-room policy

No reference prompts, task names, fixtures, solutions, hidden tests, source
archives, or checkouts may enter this tree. Audit tools verify this at byte
level (exact hashes, archive members, fixed-size blocks, long n-grams, canary
strings) and at provenance level (shared source repositories).

## Large binary assets

Five large fixture binaries (>20MB) are gitignored and distributed via the
HuggingFace dataset `eewer/general-agent-bench-results` under `v2/assets/`
(see `specs/large_assets.json` for sha256 + upstream sources):

- `tasks/prism-bridge/environment/hadoop-3.3.6.tar.gz` (697MB)
- `tasks/harbor-gasket/environment/files/releases/node-v20.19.3-linux-x64.tar.xz` (25MB)
- `tasks/zephyr-orchid/environment/files/model/vosk_model.zip` (40MB)
- `tasks/raven-orchid/environment/files/vosk-model/graph/{Gr,HCLr}.fst` (45MB)

Fetch from the dataset (or upstream), verify sha256, place at the repo path,
then the task images build normally.

## Traces, results, and audit evidence

All benchmark traces (pi and terminus-2 runs on glm-5.3-flash), oracle sweeps,
grading-audit forensics, blind-review verdicts, and the independence report are
archived in the HF dataset `eewer/general-agent-bench-results` under `v2/`
(see `v2/README.md` in the dataset). Branch: `general-v2-eval`.
