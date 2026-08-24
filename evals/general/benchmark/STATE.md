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

1. ~~**Verifier-strictness sweep**~~ DONE (2026-08-24, new machine):
   - `skill-indexes`: verifier read `/app/answer.txt` but instruction says
     `/app/result.txt` → verifier + solve.sh + instruction example aligned to
     `/app/result.txt`. Oracle: PASS.
   - `skill-cli-argument-handling`: verifier checked a *stale*
     `parsed.json` (agent correctly ran both stipulated invocations, last one
     leaves run-2 state) → verifier now runs the parser itself, checks both
     contract invocations + interleaved/short-form + rejection behavior.
     Oracle: PASS.
   - `skill-git-reflog`, `skill-stdin-stdout` (previously fixed) re-oracle:
     PASS. `item-040-main` (0–100 → [0,1] scale) re-oracle: 1.0.
2. **Triage run-1's 32 zeros** (done 2026-08-24):
   - Verifier bugs FIXED:
     - `skill-image-normalization`: instruction says `norm.txt`, verifier +
       solve.sh used `normalization.txt` → aligned to `norm.txt`. Oracle: PASS.
     - `item-048-main`: exact `top2` equality while similarity allows 1e-4
       tolerance → verifier now tolerates near-tie swaps (<1e-4). Oracle: 1.0.
     - `skill-http-server`: verifier made more robust (retry curl for 30s,
       second pkill) — the zero was likely a start-timing race.
     - `skill-post-receive-hooks`: verifier push stderr was hidden
       (`2>/dev/null`) → now logs push rc/output/hook.log for diagnosis.
   - Verifier bugs disproven / GENUINE model failures:
     - `skill-open-english-wordnet-schema` — agent's traversal wrongly
       included the root synset; verifier correct.
     - item-009-main, item-022-main, item-057-main, item-072-main,
       item-021-hard, item-022-hard, item-032-hard, item-037-hard,
       item-045-hard, item-046-hard, item-070-hard, item-072-main,
       skill-assembly-like-addressing, skill-cli-abi, skill-history-rewriting,
       skill-feal-like-cipher, skill-mp4-video-frames, skill-pmars-core-war,
       skill-mips-instruction-set, skill-differential-cryptanalysis,
       skill-telnet (NonZeroAgentExitCodeError exit 143 = transient, retry).
   - Exceptions overlapping zeros: item-009-main, item-055-main,
     skill-pipeline-parallelism had AgentTimeoutError.
3. **Exceptions from run-1** (handled 2026-08-24):
   - 17 EnvironmentStartTimeoutError → bumped
     `environment.build_timeout_sec` to ≥2400 (3600 for the 1800s ones) on all
     16 env-timeout tasks.
   - 7 AgentTimeoutError → bumped `[agent] timeout_sec` to 2400s on
     item-001-main, item-005-{main,hard}, item-009-main, item-032-hard,
     item-055-main, skill-pipeline-parallelism (+ item-048-hard).
   - 4 RuntimeError (docker compose) + 1 NetworkConnectionError + 2
     NonZeroAgentExitCodeError → transient; fixed by re-run.
   - NOTE: final run can go up to concurrency ~32 (2GB per container healthy
     on the new 64GB machine). Sequential harbor invocations only — parallel
     harbor processes corrupt shared scratch state.
4. Re-oracle sweep **oracle2** (jobs-oracle2/): first pass hit two infra
   issues — disk-full (reclaimed ~120GB: docker build cache, uv/HF caches,
   duplex-model dirs) and docker bridge-network exhaustion
   ("all predefined address pools fully subnetted" — fixed by pruning
   networks between chunks; do NOT run parallel harbor invocations).
   Second pass (o2-re-chunk-*, 250 tasks) completed: ~96% oracle-green.

   Oracle-broken tasks found & FIXED (2026-08-24/25):
   - item-004-main: tests/test_check.py defined main() but never called it
     (reward.txt never written → always 0).
   - item-005-hard: pmars-src.tar.gz ships stale macOS Mach-O .o files;
     oracle now `rm -f *.o` before make.
   - item-013-main: configure wrote `# generated by configure` (invalid C
     directive) into deploy.h → `/* ... */`.
   - item-013-hard: oracle now also handles -Werror=unused-result on fread.
   - item-019-main: oracle never wrote the repaired WAL bytes back to disk.
   - item-034-main: ws_bridge.py had THREE bugs — missing `import time`,
     called nonexistent `client_to_tcp()` (→ client_to_target), missing
     `--path` argparse option. Bridge now verified end-to-end.
   - item-055-main: Dockerfile COPY created /app/polyglot/polyglot/
     (nested); oracle main.rs had rust compile errors (collect::<String>,
     char subtraction, u64 overflow on fib(93) → wrapping_add).
   - item-057-main: oracle NameError (J → overlap).
   - item-058-hard: oracle final_goal proof wrong (induction leaves
     (y+z)+0); fixed with comm+assoc two-rewrite proof.
   - item-075-main: oracle verified exploit but never wrote the deliverable
     /app/payload.bin.
   - item-075-hard: UTF-8 decode error in ELF section-name parse →
     decode('utf-8','replace').
   - skill-assembly-like-addressing: verifier didn't skip the '#'
     comment line in ea.txt.
   - skill-async-process-i-o: oracle only wrote solver.py, never ran it.
   - skill-configure: Dockerfile-generated server_app.py defined load()
     but never called it → always printed nothing.
   - skill-differential-cryptanalysis: S-box output diffs span 0..255 but
     task/verifier/oracle assumed 0..15 → respecified to 256-line
     distribution.
   - skill-gdb-objdump: gcc -O2 folds the secret into movabs immediates
     (no .rodata string); oracle now recovers it from disassembly.
   - skill-history-rewriting: test.sh missing `then reward=1` after the
     python heredoc (reward could never be set).
   - skill-pip-index-url: PEP 503 layout wrong (wheel+index not under
     /myprobe/ project page).
   - skill-relu-piecewise-linear-analysis: oracle ran /app/relu.py but
     never wrote it.
5. Iterate run → audit → fix until grades stabilize across two runs.
6. **Final full run**: `p` + deepseek-v4-flash-0731, k=1, concurrency up to
   32 (single harbor invocation, not parallel). Prune docker networks
   between runs; keep ≥40GB disk free.

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
