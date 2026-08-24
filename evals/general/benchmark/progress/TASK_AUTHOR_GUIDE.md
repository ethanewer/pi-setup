# Harbor task authoring guide (read carefully — every subagent MUST follow it)

You are authoring tasks for a **Harbor** benchmark of general coding-agent ability.
Harbor runs each task in a Docker container: it builds `environment/`, starts a
container, gives the agent `instruction.md`, lets the agent work, then runs
`tests/test.sh` which must write a numeric reward to `/logs/verifier/reward.txt`.

## Directory layout (exact)

```
tasks/<task-name>/
  task.toml              # harbor config (schema_version = "1.4")
  instruction.md         # the ONLY thing the agent sees as its goal
  environment/
    Dockerfile           # builds the task container
    files/               # optional; copied into image (COPY files/ /app or similar)
  solution/
    solve.sh             # oracle solution: bash script run inside the container
  tests/
    test.sh              # verifier; MUST write 0/1 (or 0..1) to /logs/verifier/reward.txt
```

## task.toml

```toml
schema_version = "1.4"

[metadata]
difficulty = "easy" | "medium" | "hard"
category = "<one of: programming | debugging | data_processing | data_science | security | system_administration | file_operations | scientific_computing | web | reasoning>"
tags = ["<slug-of-each-covered-skill>", "item-NNN" (if item task)]

[verifier]
timeout_sec = 300.0        # bump for slow test suites

[agent]
timeout_sec = 900.0        # easy 600, medium 900-1200, hard 1800-3600

[environment]
build_timeout_sec = 600.0
cpus = 1                   # 2 for ML / compilation-heavy tasks
memory_mb = 2048           # 4096 for PyTorch/ML tasks
storage_mb = 4096          # 8192+ for ML tasks
```

## Base images (IMPORTANT — corporate TLS proxy)

Always use one of the prebuilt local base images as your FROM:

- `bench-base:ubuntu-24.04`  — ubuntu 24.04 + curl/git/python3/jq, CA-patched
- `bench-base:python-3.12`   — python:3.12-slim + curl/git/jq, CA-patched (PREFERRED for Python tasks)
- `bench-base:node-22`       — node:22-slim + python3, CA-patched (for JS/Node tasks)

These already include the corporate root CA so HTTPS works. For OS packages:
`RUN apt-get update && apt-get install -y <pkgs> && rm -rf /var/lib/apt/lists/*`.
For pip: works out of the box (PIP_CERT set). For heavy preinstalled toolchains
(r-base, texlive, coq, golang, rust) you may start FROM the official image
(e.g. `FROM r-base:4.4`) but then you MUST add the CA patch as the first layer:

```dockerfile
COPY corp-root-ca.pem /usr/local/share/ca-certificates/corp-root-ca.crt
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && update-ca-certificates && rm -rf /var/lib/apt/lists/*
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt
```

(Ask for `certs/corp-root-ca.pem` to be copied into `environment/` in that case —
it is available at `benchmark/certs/corp-root-ca.pem`.)

Set `WORKDIR /app` in every Dockerfile.

## Verifier rules

- `tests/test.sh` runs as root from the task workdir AFTER the agent finishes.
- It MUST always write a reward: end with `echo "$reward" > /logs/verifier/reward.txt`
  (never rely on exit code alone; never `set -e` yourself into skipping the write).
- Standard pattern: run a checker (bash or `python3 - <<'EOF'` or pytest) that exits
  non-zero on failure; map exit 0 -> reward 1, else 0.
- Partial credit is allowed for multi-part item tasks: emit a fraction (e.g. 0.5)
  via `/logs/verifier/reward.txt` when roughly half the checks pass. Keep the
  thresholds simple and deterministic.
- Verifiers must be **objective**: check file existence/content, run the produced
  program and compare outputs, recompute expected values from fixed inputs. Never
  just grep the instruction. Hidden-check files that the agent cannot see should
  live ONLY in `tests/` (they are copied to /tests at verify time, not into the image).
- Make tests robust: `mkdir -p /logs/verifier`, tolerate CRLF, round floats with
  tolerance, don't depend on agent file layout beyond what instruction.md specifies.

## Instruction rules

- instruction.md must be fully self-contained and unambiguous: exact input paths,
  exact output paths, exact formats, edge cases, and constraints. The agent gets
  NO other context.
- For tasks that ask to "run an evaluator and inspect failures", ship a runnable
  evaluator script in the environment and reference it in the instruction.
- Do not leak the solution or expected answers into the image (except inputs the
  agent legitimately needs).

## Solution rules

- `solution/solve.sh` must fully solve the task from the pristine container state
  when run as root (bash, no network assumptions beyond what's in the image).
  Keep it simple and deterministic; it is the oracle.
- If the solution needs files, embed them with heredocs.

## Difficulty calibration

- easy/trivial: one focused action or fact; solvable in a few commands.
- medium: multi-stage (read contract -> implement -> run evaluator -> fix).
- hard: deep multi-stage; requires the item's full soft+technical skill set;
  adversarial/ambiguous inputs; iterative verification against quantitative scores.

## Reference corpora (USE THESE as starting points)

- `reference/corpus/nem-easy-*` and `reference/corpus/nem-med-*`: complete Harbor
  tasks from NVIDIA Nemotron-Terminal-Synthetic-Tasks (instruction.md, task.toml,
  environment/Dockerfile + files/, tests/test.sh + test_outputs.py). You may adapt
  one wholesale (rewrite their Dockerfile FROM line to a bench-base image and strip
  the `[environment] docker_image` key from their task.toml — those point at an
  internal NVIDIA registry).
- `reference/corpus/tmax-*`: TMax-15K tasks with task.json, setup.sh, fixtures,
  test_initial_state.py / test_final_state.py, container.def. Adapt the scenario +
  tests into Harbor layout.
- See `reference/corpus/MANIFEST.json` for the index.

## Absolute requirements before you finish a task

1. All 5-6 files exist and are non-empty.
2. Dockerfile starts FROM a bench-base image (or CA-patched official image).
3. tests/test.sh writes /logs/verifier/reward.txt on every path.
4. solve.sh genuinely produces the reward=1 state.
5. Deterministic: same container input => same expected output.
