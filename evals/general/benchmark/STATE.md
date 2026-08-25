# general-agent-bench — state & handoff

A benchmark of **general coding-agent ability**, built on
[harbor](https://github.com/harbor-framework/harbor). Tasks are derived from
`../skills.json` (76 skill items with agentic soft-skills + technical skills).

Verified as of 2026-08-25 02:00 CDT (post machine restart; all numbers below
were re-checked against the job directories on disk).

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
jobs/                    harbor run outputs (gitignored) — run-1, run-2, misc jobs
jobs-oracle2/            oracle sweep-2 outputs (gitignored), collected by
                         tools/collect_oracle2.py -> specs/oracle2_report.json
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
for name in ["benchmark-jobs.tar.gz",              # run-1 + misc harbor jobs
             "benchmark-jobs-run2-run3.tar.gz",     # run-2 + run-3 (FINAL) jobs
             "benchmark-traces-full.tar.gz",        # EVERYTHING: jobs/ (run-1/2/3 + all
                                                    #   debugging runs) + jobs-oracle2/ (oracle sweep 2)
             "benchmark-reference-corpus.tar.gz",   # reference/corpus seeds
             "benchmark-specs-progress.tar.gz"]:    # specs/ + progress/
    p = hf_hub_download("eewer/general-agent-bench-results",
                        name, repo_type="dataset")
    print(p)
PY

tar xzf benchmark-jobs.tar.gz            # -> jobs/
tar xzf benchmark-jobs-run2-run3.tar.gz  # -> jobs/ (run-2 + run-3)
tar xzf benchmark-traces-full.tar.gz     # -> jobs/ + jobs-oracle2/ (all traces)
tar xzf benchmark-reference-corpus.tar.gz  # -> corpus/ (move under reference/)
tar xzf benchmark-specs-progress.tar.gz    # -> specs/ progress/
```

The key result file is `jobs/<job-name>/result.json` plus per-trial dirs
with `agent/pi.txt` (full JSON-mode transcript), `verifier/`, and
`result.json`.

## Current state (verified 2026-08-25)

### Tasks & oracle: DONE

- 524/524 tasks authored, all lint-clean (`python3 tools/lint_tasks.py`
  → "524 ok, 0 bad").
- Oracle validation sweep-2 (`jobs-oracle2/`, `python3 tools/collect_oracle2.py`):
  **518 green, 0 zero, 6 partial, 0 errored, 0 missing**.
  The 6 partials are correct oracle scores, not defects:
  - Graded/staged evaluators by design: item-014-main 0.3, item-033-hard 0.8,
    item-041-hard 0.4, item-044-main 0.86
  - item-043-main 0.6 and item-043-hard 0.6: both MCMC fits run, but the
    oracle's own fits trip the hard convergence gates (rhat/n_eff/cross-check)
    — the honest oracle score; the same gates apply to any agent.
- All ~30 task/verifier/environment bugs found during run-1 triage and the
  oracle2 sweep are FIXED and committed (see git log: `Fix 20+ oracle-broken
  tasks...`, `Fix 8 more oracle-broken tasks...`, the item-043 series
  ending at `Oracle complete: 524/524 accounted`). Git tree clean, in sync
  with origin/main.

### Benchmark runs

| run | config | result |
|-----|--------|--------|
| run-1 (`jobs/deepseek-flash-run-1`, 2026-08-24, pre-fix) | p_agent + deepseek-v4-flash-0731, -n 20, k=1 | 502/524 scored, **457 pass (91.0% of scored)**, 31 exceptions, $2.05, 37.1M in / 1.56M out tokens. Mean reward 1.075 is INFLATED by the pre-fix item-040-main 0–100 scale bug. |
| run-2 (`jobs/deepseek-flash-run-2`, 2026-08-24→25, post-fix) | same agent/model, -n 24, k=1 | 524/524 trials ran; **522 scored**, **489 pass (93.7% of scored)**, mean reward **0.9494**, 11 partial, 22 zero, 11 exceptions. |
| run-3 (`jobs/deepseek-flash-run-3`, 2026-08-25, FINAL — post-triage fixes) | same agent/model, -n 24, k=1, wall 2h20m | **524/524 trials, 522 scored**, **488 pass (93.5% of scored)**, mean reward **0.9411**, 9 partial, 25 zero, 13 exceptions (11 AgentTimeout, 2 NonZeroExit). Verified by `tools/audit_benchmark.py`: 0 missing, anomalies fully triaged (below). |

Run-2 caveats:
- `result.json` was written mid-execution (finished_at = null): the PC was
  restarted while the last trial (item-043-hard) was still running; harbor
  was killed. Stats above were recomputed directly from the per-trial
  verifier/reward.txt files.
- **item-043-hard: UNSCORED** in run-2 (killed mid-trial; the subsequent
  single-task rerun was stopped and its incomplete job dir removed).
- **item-054-main: reward.txt is EMPTY** — the agent hit the 1200s timeout
  (not bumped like the other timeout tasks), never built /app/pov/tracer,
  and tests/test.sh crashes with FileNotFoundError on the missing binary
  instead of writing reward 0. Both bugs still unfixed (see below).

### Run-2 exceptions (11)

- AgentTimeoutError (6): item-005-main (2400s), item-054-hard (2400s),
  item-054-main (1200s — needs bump), item-069-main (1500s — needs bump),
  item-072-main (1800s — needs bump), item-076-hard (2400s)
- NonZeroAgentExitCodeError exit 143 (5, SIGTERM, same transient class as
  run-1): item-033-main, item-034-hard, item-035-main, item-043-main,
  item-061-hard. Several of these still scored partial credit.

### Run-2 zeros (22)

- Zero in BOTH runs (11 — model legitimately fails these; oracle green):
  item-009-main, item-021-hard, item-022-hard, item-022-main,
  item-057-main, item-070-hard, item-072-main, skill-feal-like-cipher,
  skill-mips-instruction-set, skill-pmars-core-war, skill-post-receive-hooks
- item-034-hard: zero due to exit-143 (run-1 scored it 0.7)
- **REGRESSIONS — passed 1.0 in run-1, zero in run-2 (10, NEED TRIAGE)**:
  item-064-hard, item-069-hard, item-069-main (AgentTimeout 1500s),
  item-070-main, item-076-hard (AgentTimeout 2400s),
  skill-node-js-qemu-like-vm, skill-port-forwarding (empty verifier stdout),
  skill-static-binary-analysis, skill-vimscript-macros,
  skill-warrior-benchmarking.
  Two zeros are explained by agent timeouts; the other 8 need per-trial
  inspection (verifier change vs agent variance vs task bug).

### Machine state (verified)

- No harbor/monitor processes running; no containers running; git tree clean.
- bench-base:{ubuntu-24.04,python-3.12,node-22} images present.
- Env vars set: OPENROUTER_API_KEY, HF_TOKEN, DOCKER_USERNAME/DOCKER_PAT.
- Disk: 539G drive, ~124G free. Docker build cache holds ~45GB reclaimable
  layers (kept on purpose — they make the next full run's image rebuilds
  fast; `docker builder prune -af` only if disk gets tight). ~116 leftover
  task/test images (207GB) from run-2 are also reclaimable if needed — do
  NOT delete `alexgshaw/*` images.

## Remaining tasks (in order)

**ALL DONE 2026-08-25.** Run-3 (`deepseek-flash-run-3`) is the
**FINAL** benchmark result. Steps 1–4 were the 2026-08-25 triage pass
(documented below); step 5's stability call resolved in run-3's favor:
488 pass reproduces run-2's 489 within ±1 (mean 0.9411 vs 0.9494).
Step 6 (audit/commit/report/archive) is complete; see "Final result".

## 2026-08-25 triage pass (all remaining-tasks 1–4 DONE)

Task/timeout fixes applied (git-committed):

- item-054-main: agent timeout 1200 → 2400; tests/test.sh no longer
  crashes when /app/pov/tracer is missing — always writes reward.txt
  (fail-closed 0.0000 for empty/garbage output too). Unit-tested both
  branches locally.
- item-069-main: timeout 1500 → 2400; item-072-main: 1800 → 2400.
- skill-post-receive-hooks: verifier bug — its scratch push was rejected
  (non-fast-forward) when the agent had already test-pushed to master.
  Verifier now force-pushes (hook fires identically).
- skill-port-forwarding: verifier bug — the agent's leftover test server
  on 9097 (any cmdline, e.g. `python3 -c`) shadowed the verifier's
  server because only exact-cmdline pkill was used. Verifier now frees
  8090+9097 via fuser/pkill, polls the source server until it answers,
  and retries the tunnel check.
- skill-static-binary-analysis: instruction example shows
  `elf=file format elf64-x86-64` but the verifier only accepted the
  stripped form (run-1 pass was luck of model phrasing). Verifier now
  accepts both forms.
- item-070-main: instruction clarified — when `gcov -n` prints several
  `Lines executed:` lines (fortified headers + total), the summary line
  is the FIRST one (the sqlite3.c line). Oracle and verifier already
  agreed on this; agent variance, not a bug.

Run-2 zero-triage verdicts (per-trial transcript + verifier inspection):

- Genuine agent failures: item-064-hard (wrong verdicts, agent falsely
  claimed done), item-069-hard (turn ended mid-plan without executing),
  skill-node-js-qemu-like-vm (VM emitted wrong sequence),
  skill-vimscript-macros (model ended turn after ~4.8k reasoning tokens
  with zero tool calls), skill-warrior-benchmarking (agent phrasing
  matched none of the verifier's concept keywords repeat|iteration|
  multiple — keyword contract is by design).
- Genuine budget limits (already at 2400s): item-005-main,
  item-054-hard, item-076-hard.
- Timeouts fixed by bumps: item-069-main, item-072-main, item-054-main.
- Transient: item-034-hard (SIGTERM exit-143 from machine restart).
- Verifier bugs fixed: skill-post-receive-hooks, skill-port-forwarding,
  skill-static-binary-analysis (see above).

All changed tasks were oracle re-checked (jobs-oracle3/) before run-3:
skill-post-receive-hooks 1, skill-static-binary-analysis 1,
skill-port-forwarding 1, item-054-main 1.0000.

## Final result (run-3, 2026-08-25)

`p_agent` (pi lean profile) + `openrouter/deepseek/deepseek-v4-flash-0731`,
524 tasks, k=1 rollout each, concurrency 24, wall clock 2h20m:

- **Pass (reward 1.0): 488 / 522 scored (93.5%); 488/524 overall**
- **Mean reward: 0.9411**
- Partials (9): item-005-hard 0.744, item-014-main 0.3,
  item-014-hard 0.4, item-033-hard 0.8, item-034-hard 0.7,
  item-035-main 0.8, item-041-hard 0.4, item-047-main 0.5,
  item-073-main 0.5 (graded/staged evaluators, same as oracle).
- Exceptions (13): 11 AgentTimeoutError (item-001-main/hard*,
  item-005-main, item-036-hard, item-043-main, item-043-hard*,
  item-045-hard, item-072-hard, item-076-hard,
  skill-pipeline-parallelism; *no reward.txt written, counted zero)
  + 2 NonZeroAgentExitCodeError (item-034-main scored 1.00,
  item-035-main scored 0.80 — exit-code noise, artifacts fine).
- Fixed-task confirmation: skill-post-receive-hooks, skill-port-
  forwarding, skill-static-binary-analysis, item-054-main all 1.0;
  item-069-main and item-072 timeout bumps took effect (069-main
  passed; 072-main ran to completion but its fastText model was
  degenerate — genuine verifier catch).
- Run-3 zero deltas vs run-2: timeouts move around with agent
  execution-time variance (036-hard, 045-hard, 072-hard,
  pipeline-parallelism, 001-main/hard, 043-main/hard timed out this
  time; 054-hard/069-main passed this time). Genuinely new failures:
  item-046-hard, item-049-main, item-074-hard, skill-cli-abi,
  skill-gdb-objdump, skill-port-process-management, item-072-main
  (degenerate model). skill-node-js-qemu-like-vm fails again (genuine).
- Stability: run-2 489 pass / 0.9494 vs run-3 488 pass / 0.9411 →
  post-fix result reproduces; run-3 is the benchmark of record.


## Ops notes (learned the hard way)

- NEVER run parallel harbor invocations — they corrupt shared scratch state
  (FileNotFoundError on trial dirs) and exhaust docker bridge networks.
  Sequential chunks only; `docker network prune -f` between chunks.
- Keep ≥40GB disk free; prune `docker builder prune -af` between big runs.
- Concurrency: up to ~32 is OK (64GB RAM, 24 cores; ~2GB per container);
  run-2 used -n 24 cleanly.
- Harbor job names must be unique (FileExistsError on reuse) — delete the
  old job dir first or pick a new name.
- Verifiers must match the instruction contract (agent-facing spec is
  authoritative) and MUST always write /logs/verifier/reward.txt.
- RStan/PyStan env (item-043-main/hard, skill-rstan-2-32-7): needs cmake
  in the Dockerfile, pip --break-system-packages (PEP 668), and ~1h
  build+fit time; verifier/build timeouts are 3600s.

## Re-running

```bash
# oracle-check a task
harbor run -p tasks/<name> -a oracle -y -o jobs-oracle2 --job-name o2-check-<name>

# full benchmark (single invocation, concurrency 24)
PYTHONPATH=$PWD/agents harbor run -p tasks -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 24 -k 1 -y -o jobs --job-name deepseek-flash-run-3

# audit a run / oracle status / lint
python3 tools/audit_benchmark.py <job-name>
python3 tools/collect_oracle2.py
python3 tools/lint_tasks.py
```

## Machine notes

- Base images `bench-base:{ubuntu-24.04,python-3.12,node-22}` must be built
  from `bases/` on a machine behind the corporate TLS proxy (they embed
  `certs/corp-root-ca.pem`). On a normal network, plain `ubuntu:24.04` /
  `python:3.12-slim` / `node:22-slim` work fine — either retag them locally
  as the bench-base names or sed the FROM lines.
- `reference/` full corpora (12GB) are NOT archived — re-download from HF if
  needed (NVIDIA Nemotron-Terminal-Synthetic-Tasks, allenai/TMax-15K,
  nebius/SWE-rebench-V2). Only the 76-task sample corpus is on HF.
