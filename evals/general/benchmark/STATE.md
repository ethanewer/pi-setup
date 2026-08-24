# general-agent-bench — state & handoff

A benchmark of **general coding-agent ability**, built on
[harbor](https://github.com/harbor-framework/harbor). Tasks are derived from
`../skills.json` (76 skill items with agentic soft-skills + technical skills).

## Goal

Measure how well a general coding agent (the local `p` pi setup, running
`openrouter/deepseek/deepseek-v4-flash-0731`) handles a broad spread of
terminal/coding tasks: legacy toolchain builds, security patching, forensics,
Scheme interpreters, git surgery, ML pipelines, deployment, and more.

## Layout (this directory = `evals/general/benchmark`)

```
tasks/                   524 Harbor tasks (see below)
agents/p_agent.py        custom Harbor agent reproducing the `p` pi lean profile
bases/                   prebuilt bench-base:* Dockerfiles (corporate CA baked in)
certs/corp-root-ca.pem   corporate TLS-intercept root CA (needed on this machine)
specs/                   plan.json, buckets, audit reports, oracle reports
reference/corpus/        76 sampled reference tasks (Nemotron/TMax) used as seeds
tools/                   make_plan.py, lint_tasks.py, oracle sweeps, audit, run scripts
progress/                task-authoring guide + pipeline notes
jobs/                    harbor run outputs (gitignored; archived to HF, see below)
```

Task tiers:
- `<item-id>-main` — easy/medium task covering all soft+technical skills of the item
- `<item-id>-hard` — hard variant when combined skill depth ≥ 8 (64 items)
- `skill-<slug>` — trivial probe per unique technical skill (384 skills)
- `golden-example` — sanity task

## Downloading the run results

Logs, trajectories, and verifier outputs live in the **private** HF dataset
`eewer/general-agent-bench-results`:

```bash
pip install huggingface_hub
huggingface-cli login  # needs read access to eewer/*

python3 - <<'PY'
from huggingface_hub import hf_hub_download
for name in ["benchmark-jobs.tar.gz",              # all harbor runs incl. deepseek-flash-run-1
             "benchmark-reference-corpus.tar.gz",  # reference/corpus seeds
             "benchmark-specs-progress.tar.gz"]:   # specs/ + progress/
    p = hf_hub_download("eewer/general-agent-bench-results",
                        name, repo_type="dataset")
    print(p)
PY

tar xzf benchmark-jobs.tar.gz       # -> jobs/
tar xzf benchmark-reference-corpus.tar.gz  # -> corpus/ (move under reference/)
tar xzf benchmark-specs-progress.tar.gz    # -> specs/ progress/
```

The key result file is `jobs/deepseek-flash-run-1/result.json` plus per-trial
dirs with `agent/pi.txt` (full JSON-mode transcript), `verifier/`, and
`result.json`.

## What's done

- 524/524 tasks authored, all lint-clean (`tools/lint_tasks.py`)
- Oracle validation: full sweep done, ~493/524 oracle-green (94%+)
- **Benchmark run-1 complete** (`jobs/deepseek-flash-run-1`):
  `p` agent + deepseek-v4-flash-0731, concurrency 20, k=1
  → **456/524 pass (87.0%)**, $2.05, 37.1M input / 1.56M output tokens
- Audit round-1 (`specs/audit_deepseek-flash-run-1.json`): 32 zero, 30
  exceptions, 13 partial. Fixed so far: item-040-main reward scale (0–100 →
  [0,1]), skill-git-reflog (verifier newline strictness + solve.sh `set -e`
  loop bug), skill-stdin-stdout (newline strictness).

## What remains (in order)

1. **Verifier-strictness sweep**: same trailing-newline fix for
   `skill-cli-argument-handling`, `skill-indexes`; re-oracle them + item-040.
2. **Triage run-1's 32 zeros** into verifier-bug vs genuine-model-failure.
   Likely verifier bugs: skill-http-server, skill-post-receive-hooks,
   skill-image-normalization, skill-open-english-wordnet-schema, item-048-main.
   Likely genuine (keep): skill-pmars-core-war, skill-differential-cryptanalysis,
   skill-mips-instruction-set, item-021-hard, item-045-hard, …
3. **Exceptions from run-1**: 17 EnvironmentStartTimeoutError → final run at
   concurrency ~12 and/or bump `environment.build_timeout_sec`;
   7 AgentTimeoutError → bump `[agent] timeout_sec` on heavy tasks;
   4 RuntimeError + 1 NetworkConnectionError → retry.
4. Re-oracle changed tasks (full sweep @ concurrency 8).
5. Iterate run → audit → fix until grades stabilize across two runs.
6. **Final full run**: `p` + deepseek-v4-flash-0731, k=1, concurrency ~12.

## Re-running

```bash
# oracle-check a task
harbor run -p tasks/<name> -a oracle -y -o jobs

# full benchmark
PYTHONPATH=$PWD/agents harbor run -p tasks -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 12 -k 1 -y -o jobs --job-name deepseek-flash-run-2

# audit a run
python3 tools/audit_benchmark.py <job-name>
```

## Machine notes

- Base images `bench-base:{ubuntu-24.04,python-3.12,node-22}` must be built
  from `bases/` on a machine behind the corporate TLS proxy (they embed
  `certs/corp-root-ca.pem`). On a normal network, plain `ubuntu:24.04` /
  `python:3.12-slim` / `node:22-slim` work fine — either retag them locally as
  the bench-base names or sed the FROM lines.
- `reference/` full corpora (12GB) are NOT archived — re-download from HF if
  needed (NVIDIA Nemotron-Terminal-Synthetic-Tasks, allenai/TMax-15K,
  nebius/SWE-rebench-V2). Only the 76-task sample corpus is on HF.
