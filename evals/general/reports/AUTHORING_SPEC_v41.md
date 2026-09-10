# Authoring spec for the v4.1 coverage-expansion wave

You are authoring ONE task in the general-agent-bench suite at
`/home/ee/pi-setup/evals/general`. Read this whole file before writing anything.
The suite already has 785 tasks and a full gate pipeline; a task that does not
pass the gates is worse than no task, because it silently breaks the release.

Your task slot, name, gap area and brief are given in your prompt. Do not change
the name. It was pre-allocated so parallel authors do not collide.

## Why this wave exists

`reports/v3.9_skill_gap_review.md` measured the published v3.9 results against
the task tree. Read it. The short version:

- 81% of tasks build `FROM bench-base:python-3.12`. The whole suite ships 760
  `.py` files, 112 `.c`, 13 `.js`, 3 `.rs`, 0 `.ts`, 0 `.go`, 0 `.css`.
- Median files shipped in `environment/files` is 1. Median shipped source is 0
  lines. Max is 1,137. No task ships a `.git` directory.
- 465 of 785 tasks are passed by all six harness/model pairs.
- The suite's own rubric scores `unsafe_action_penalty` 0 on 472 of 515 tasks,
  `resource_pressure` 0 on 414, `interaction_statefulness` 0 on 379.

This wave closes those gaps. Every task you author must be something the
existing suite cannot already measure.

## Hard constraints

1. `cpus = 1` in `task.toml` `[environment]`. The user asked for single-CPU
   tasks so the sweep runs efficiently. Do not declare more.
2. Because `cpus = 1`, any numeric thread pool must be pinned to 1. Set
   `ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
   NUMEXPR_NUM_THREADS=1` in the Dockerfile if the task touches numpy, torch,
   scipy or OpenMP. `tools/pin_numeric_threads.py --apply` will patch it for you
   if you forget, but write it yourself.
3. Only these base images: `bench-base:python-3.12`, `bench-base:ubuntu-24.04`,
   `bench-base:node-22`, `texlive/texlive`. `tools/lint_tasks.py` rejects
   anything else. Install extra toolchains with `apt-get` or `pip` in your own
   task Dockerfile; do not invent a new base.
4. No network at trial time. The container runs with `network_mode: none`.
   Anything the task needs must be baked into the image or shipped in
   `environment/files`. Network IS available while the image builds.
5. Do not vendor an upstream source repository. The clean-room policy forbids it
   and `tools/audit_independence_stream.py` enforces it. Write every fixture
   codebase yourself. If your slot says "8,000 line repository", you generate
   that repository with a script you write, from a grammar you design. It must
   be plausible, internally consistent, and compile/run.
6. Reward is binary. `tests/test.sh` writes `/logs/verifier/reward.txt`
   containing exactly `1` or `0`. `tools/check_binary_reward.py` proves this
   statically by building the value cone of every expression that reaches the
   file. No partial credit, no `passes/total`, no weighted accumulators.
7. Reward on every exit path. Start `test.sh` with the standard trap:

```bash
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
```

   Every failure path must `exit 0` AFTER writing `0`, or `exit 1` before
   writing anything so the trap writes `0`. A path that writes `0` and then
   exits `0` followed by shell code that rewrites the file from `$?` is the bug
   that made `pale-heron` and `drift-marsh` score 1 on an untouched container.
8. Nothing destructive to the host, and nothing that breaks the agent. Do not
   fragment `/etc/nsswitch.conf`, do not disable DNS, do not remove `curl`.
   `hollow-notch` did the first of these and killed four of six harness/model
   pairs before they made a single model call, because two harnesses run their
   CLI inside the container and reach the LLM over the network from there.

## Layout

```
tasks/<name>/
  task.toml
  instruction.md
  difficulty.json
  environment/Dockerfile
  environment/files/...        # everything the agent starts with
  solution/solve.sh            # executable, the oracle
  solution/<anything else>     # mounted at /solution at trial time
  tests/test.sh                # the verifier
  tests/hidden/<case>/...      # >=2 hidden generalization cases
```

`environment/Dockerfile` ends with `COPY files/ /app/`. It must NOT copy
`tests/` or `solution/`; harbor mounts those at `/tests` and `/solution`.

## task.toml

```toml
schema_version = "1.4"

[metadata]
difficulty = "hard"                       # easy | medium | hard
category = "programming"                  # see the list below
verifier_kind = "executes-deliverable"    # or "answer-with-hidden-cases"
deliverables = ["/app/...", "/app/..."]   # non-empty, all under /app
tags = ["<name>", "<category>", "clean-room"]

[verifier]
timeout_sec = 600.0

[agent]
timeout_sec = 2400.0

[environment]
build_timeout_sec = 1800.0
cpus = 1
memory_mb = 4096
storage_mb = 8192
```

Categories, exactly: `programming`, `debugging`, `data_processing`,
`data_science`, `security`, `system_administration`, `file_operations`,
`scientific_computing`, `web`, `reasoning`. Note that `dependency_management`
is NOT in the lint's allowed set even though one legacy task uses it.

Tags: keep them to `[<name>, <category>, "clean-room"]` plus at most a few
hyphenated phrases. `tools/check_tb21_coverage.py` requires every tag's words to
be a subset of the words in your own task contract (task.toml, instruction,
tests, oracle, environment) or of a claimed competency name. A decorative tag
like `"kubernetes"` in a task that never mentions kubernetes is a hard error.
The simplest safe choice is the three-tag form above.

Timeouts: give the build what it needs. A task that apt-installs golang, maven
or postgresql needs `build_timeout_sec = 1800.0` or more. Give the agent at
least 2400s for hard tasks. Give the verifier at least 600s if it runs a test
suite, more if it runs one N times.

## difficulty.json

```json
{
  "rubric": {
    "dependent_stages": 2,
    "tool_breadth": 2,
    "reasoning_depth": 2,
    "debugging_ambiguity": 2,
    "adversarial_inputs": 1,
    "hidden_case_generalization": 2,
    "quantitative_correctness": 1,
    "resource_pressure": 0,
    "interaction_statefulness": 0,
    "unsafe_action_penalty": 0
  },
  "expected_expert_time_min": 90,
  "documented_probe": null,
  "notes": "..."
}
```

Exactly those ten rubric keys, integers 0..3, plus an integer
`expected_expert_time_min`. Score honestly. This wave exists because three of
those dimensions are near-dead across the suite, so if your slot is a safety,
resource-pressure or interaction task, those scores must be genuinely high and
the verifier must actually measure them.

Buckets: total 0-9 easy, 10-17 medium, 18-30 hard. `metadata.difficulty` in
task.toml must match the bucket your rubric total lands in; the existing 515
measured tasks agree exactly and `tools/check_difficulty.py` will disagree with
you loudly if they do not.

## instruction.md

Name every deliverable path literally. `lint_tasks.py` checks each entry in
`metadata.deliverables` appears as a substring of the instruction.

State the environment: what is installed, what is already on disk, what must not
be modified. State the exact output contract: file paths, key names, key order,
number formats, encodings.

Then deliberately leave the *interesting* part unspecified. The existing suite's
median instruction is 4,098 characters of exact paths and exact schemas, and no
task in it asks the agent to make a judgement call. For most slots in this wave
the instruction should say what outcome is required and NOT say which file to
edit, which of two valid designs to pick, or where the bug is.

## The verifier

`tests/test.sh` must:

- Execute every declared deliverable. For `executes-deliverable`, the literal
  path string must appear in `test.sh` or in a helper it references by
  `/tests/...` path. `lint_tasks.py` checks this.
- Run the deliverable against `tests/hidden/<case>/` fixtures, not just the
  visible ones. At least two hidden cases, and they must differ from the visible
  fixture, or the task measures memorisation.
- Assert the interesting property, not just that a file exists. A verifier that
  only checks existence is vacuous; the v3.5 negative control found three.
- Print a readable failure list to stdout before writing `0`. That text lands in
  `verifier/test-stdout.txt` and is the only way anyone later diagnoses a task.

Do not make the verifier depend on wall-clock timing unless the gate is generous
(a 3x margin at least) and the thing measured is genuinely time-bound. Timing
gates are how a correct solution starts failing on a busier host.

## The oracle

`solution/solve.sh` must be executable (`chmod +x`), must create every declared
deliverable, must do the real work, and must NOT reference `/tests` anywhere
outside a comment. `lint_tasks.py` strips comment lines and then fails on any
`/tests` occurrence. The oracle is the proof that the task is passable; an oracle
that hardcodes the answer or reads the expectations is not a proof of anything.
28 tasks in this suite were repaired in v3.4 because their own oracle could not
pass.

Put the real solver in `solution/` as a separate file (e.g.
`solution/solver.py`) and have `solve.sh` copy it to the deliverable path and run
it. That is what `larch-dial` does.

## No answer leaks

No file under `environment/` may be byte-identical to a file under `tests/` whose
name matches `expected` or `answer`. `lint_tasks.py` hashes and compares. A
byte-identical INPUT replay is allowed and only noted, but make sure your hidden
cases genuinely differ.

## Pip pins

Every `pip install` in your Dockerfile must pin exact versions: `pip install
--no-cache-dir flask==3.1.3`. `tools/pin_python_dependencies.py` resolves each
pin against the base image's own interpreter and the index the task names, and
fails on anything unpinned or on a version that base cannot install. apt packages
are deliberately not pinned.

If you need a pin you cannot guess, resolve it:

```bash
docker run --rm bench-base:python-3.12 pip index versions <pkg> 2>/dev/null | head -2
```

`bench-base:node-22` carries Python 3.11, `bench-base:ubuntu-24.04` carries
3.12.3, `bench-base:python-3.12` carries 3.12.13.

## Git repositories

If your Dockerfile runs `git init` or `git clone`, it must also write a
system-wide safe directory entry, or the trial fails as uid 1000 with "detected
dubious ownership":

```dockerfile
RUN git config --system --add safe.directory '*'
```

`tools/ensure_git_safe_directory.py` checks this. Also set a committer identity
in the Dockerfile so build-time commits work:

```dockerfile
RUN git config --system user.email "build@localhost" && git config --system user.name "build"
```

To ship a repository WITH history, generate it at build time with a script under
`environment/files/` that commits incrementally. Do not try to commit a `.git`
directory through git; it will not survive.

## Services that must be running

There is no systemd in these containers and harbor does not run the image
ENTRYPOINT in the trial container. `slate-fjord` was retired because it needed an
sshd started at container start and there was no way to bring one up. So: the
AGENT must start any service the task needs, as part of its deliverable, and the
verifier must be able to see it. The reliable patterns are

- a deliverable shell script or supervisor config the verifier invokes, then
  polls a readiness endpoint or a unix socket before asserting;
- `supervisor` (apt `supervisor`, version 4.2.5) with a config the agent writes
  and the verifier starts with `supervisord -c <path>`;
- a database started with its own initdb/pg_ctl or `redis-server --daemonize yes`
  from a deliverable script.

Always poll for readiness with a bounded loop. Never sleep a fixed time and hope.

## Verified-available toolchains on bench-base:ubuntu-24.04 (apt)

golang-go 1.22, rustc/cargo 1.75, openjdk-21-jdk-headless + maven 3.8.7,
postgresql-16, mariadb-server 10.11, redis-server 7.0.15, nginx 1.24,
prometheus 2.45.3 (ships `promtool`) and prometheus-alertmanager 0.26,
supervisor 4.2.5, sqlite3 3.45, git-lfs, jq, yq 3.1.0, python3-pytest 7.4.4.

`bench-base:node-22` has node 22.23.2 and npm on PATH via nvm, plus Python 3.11.
Use it for every TypeScript and frontend task. There is no usable headless
browser: Ubuntu's `chromium-browser` is a snap stub and `firefox-esr` is absent,
so frontend assertions must go through jsdom, `@testing-library/react` and
`axe-core` rather than a real renderer. Playwright is pip-installable on
`bench-base:python-3.12` and two existing tasks use it, but downloading a browser
at build time is fragile; prefer jsdom.

Terraform is not packaged. Download a pinned binary at build time; this URL was
verified reachable: `https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip`.
MongoDB is not available on noble; do not plan a task around it. DuckDB is
pip-installable and is a fine substitute for an analytical-store task.

Registries verified reachable at build time: pypi.org, registry.npmjs.org,
proxy.golang.org, index.crates.io and static.crates.io, repo.maven.apache.org,
deb.debian.org, archive.ubuntu.com, releases.hashicorp.com, get.helm.sh.

## Acceptance: you must prove it in both directions

Do not report a task as done until this passes:

```bash
cd /home/ee/pi-setup/evals/general
bash tools/verify_new_task.sh <name>
```

It runs the seven static gates, then `harbor run -a oracle` (reward must be 1)
and `harbor run -a nop` (reward must be 0), then deletes the images it built so
the host disk survives the wave. Exit 0 means the task is accepted.

The nop half is not optional and is the one authors skip. Your verifier must
score 0 on a container where no agent ran. If it scores 1, your verifier is
vacuous and the task measures nothing.

Iterate until both pass. If after real effort a slot is not achievable in this
harness, say so plainly in your final report with the reason, and leave the
directory out rather than shipping a task that cannot pass its own oracle. Do not
weaken the verifier to make the oracle pass; fix the oracle or fix the task.

Budget your time. A hard task with a generated 8,000-line repository is a large
piece of work. Prefer a smaller repository that is real and consistent over a
large one that does not build.

## What NOT to do

- Do not edit any file outside `tasks/<your-name>/`. Other agents are authoring
  other tasks concurrently. `specs/` is updated centrally after the wave.
- Do not run `tools/build_coverage.py`, `tools/build_difficulty.py`,
  `tools/update_provenance.py` or anything that rewrites `specs/`.
- Do not run `docker system prune`, `docker builder prune` or
  `docker image prune -a`. Another live job is running 28 containers on this
  host. `verify_new_task.sh` removes only the images your own runs created.
- Do not claim a tb2.1 competency (`C-xxxxxxxx` tag). These are new skill areas
  outside that inventory; they are recorded centrally as
  `claims_no_competencies`.
- Do not raise `cpus` above 1.
