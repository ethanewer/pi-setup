# Authoring addendum for the v4.2 upstream-clone family

Read `reports/AUTHORING_SPEC_v41.md` first. Everything in it still applies: the
file layout, `task.toml` shape, the binary reward contract, the reward trap on
every exit path, the difficulty rubric, the tag traceability rule, `cpus = 1`,
thread-pool pinning, hidden cases, and the both-directions acceptance gate.

This file adds what is specific to tasks that clone a real upstream repository.

## Why this family exists

Measured against the frozen Terminal-Bench 2.1 reference: 42 of its 241 tasks
(17%) put the agent inside a real upstream codebase. It clones 35 real
repositories, among them `astropy/astropy`, `apache/flink`, `apache/spark`,
`BVLC/caffe`, `opencv/opencv`, `openai/whisper`, `AbsInt/CompCert`, `stp/stp`,
`klee/klee`, `openwall/john`, `facebookresearch/fastText`, `LeelaChessZero/lc0`,
`bottlepy/bottle`, `pallets/flask`, `sudo-project/sudo`, `stan-dev/httpstan`,
`gcc-mirror/gcc` and the Linux 6.9 kernel tarball. Four of its tasks are
SWE-bench problems against real Python libraries.

This suite did that in none of its first 837 tasks. Its largest shipped codebase
is 8,144 self-authored lines. So an agent that scores well here has never been
asked to find anything in a tree it did not write, never built a project whose
build system it did not choose, and never run somebody else's test suite.

Every repository in `specs/v42_slots.json` is a substitute of similar domain and
scope for a specific TB2.1 task, and none of them is a repository TB2.1 uses.

## The hard rule: disjointness

`specs/tb21_source_repositories.json` lists all 68 repositories the frozen
reference touches, extracted from every text file under its `original-tasks/`.
Your task must not clone, download, submodule, `pip install` from git, or vendor
any of them.

`tools/check_upstream_disjointness.py` enforces this and names the offending
line. It also enforces pinning and `--depth`, and rejects any VCS fetch of an
internet host under `tests/` or `solution/`.

Watch the transitive paths, which the gate cannot see:

- `git clone --recurse-submodules` can pull a forbidden repository as a
  submodule of an allowed one. If you need submodules, list every submodule URL
  and check each against the forbidden file yourself, and say in your report
  that you did.
- `pip install -e .` or `npm install` on a real project can pull a git
  dependency. Warm the dependency cache at build time and check what it fetched.
- A project's own test suite may download fixtures at run time. There is no
  network at trial time, so such a test will fail; select tests that do not.

## Clone at build time, pinned, shallow

Network exists while the image builds and does not exist during the trial. So
every fetch goes in `environment/Dockerfile` or a script it runs.

Pin to an immutable revision and fail closed if it moves:

```dockerfile
ARG UPSTREAM_SHA=<40-hex>
RUN git clone --depth 1 --branch <tag> https://github.com/<owner>/<repo>.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*'
```

A tag alone is not a pin. Tags can be force-moved upstream, and then the
committed Dockerfile silently builds a different project than the one that was
measured. That is the same defect `tools/pin_python_dependencies.py` exists to
prevent for pip. Assert the 40-hex commit.

Resolve the SHA yourself with `git ls-remote <url> <ref>` and use the full
40 characters. The refs in `specs/v42_slots.json` were resolved on 2026-09-10
and are a starting point, not a substitute for your own check.

Use `--depth 1`. A full history for `apache/kafka` is gigabytes and buys
nothing unless the task is about the history, in which case use
`--filter=blob:none` and say why.

`git config --system --add safe.directory '*'` is required whenever the clone is
root-owned and the trial may run as uid 1000. `tools/ensure_git_safe_directory.py`
checks it.

## Never vendor upstream source into the task tree

Do not copy the cloned tree, or any part of it, into `environment/files/`. Two
reasons. It puts upstream bytes inside the tree that
`tools/audit_independence_stream.py` walks, where the block and n-gram classes
can see them and a coincidental window becomes an audit finding you have to
explain. And it makes the repository enormous for no benefit, since the
Dockerfile can fetch it.

If you need to change upstream source, ship a small authored patch or generator
script under `environment/files/` and apply it at build time. That keeps our
contribution auditable as ours and the upstream bytes out of the tree. A seeded
regression is exactly this case: write the patch, apply it in the Dockerfile, and
keep the patch small enough to read.

## Warm every cache at build time

The trial has no network, so anything the build or the test suite would fetch
must already be in the image:

- Python: `pip install` the project and its test dependencies in the Dockerfile.
  Pin exact versions; `tools/pin_python_dependencies.py` enforces this and
  resolves them against the base image's own interpreter.
- Node: run `npm install` or `npm ci` in the Dockerfile and leave `node_modules`
  in the image.
- Gradle: run the build once in the Dockerfile so `~/.gradle` is warm, and have
  the trial invoke Gradle with `--offline`.
- Maven: populate a local repository at a fixed path in the Dockerfile and have
  the trial pass `-o -Dmaven.repo.local=<that path>`.
- apt: install build dependencies in the Dockerfile. apt is not version-pinned
  in this suite, by design, because Debian rotates its archives.

If a project's own test suite downloads data at run time, do not use those tests.
Pick targeted tests that are self-contained, and say in the instruction which
ones the agent is expected to run.

## Budget for 1 CPU

`cpus = 1` is mandatory. Compile time is the real risk in this family, not clone
time: every repository in the slot list shallow-clones in under 10 seconds, but
`libvips` with meson, `redis` with make, `shadow` with autotools and one module
of `apache/kafka` with Gradle each take minutes to tens of minutes on one core.

So:

- Measure the real build time in the image before you settle the task, and set
  `build_timeout_sec` to at least three times what you measured. 3600 is a
  reasonable default for a C or C++ build and 5400 for a JVM module.
- Build only what the task needs. One Gradle or Maven module, not the whole
  project. One make target, not `make all` plus `make test` plus the docs.
- Do the expensive build once in the Dockerfile so it is a cached image layer,
  and have the agent's work be incremental on top of it. An agent that must
  rebuild a C++ project from scratch inside a 2400s trial budget will time out
  and you will have measured the timeout, not the skill.
- Set `memory_mb` for the real peak. A Gradle or Maven build wants 4096 or more.

If a build is genuinely intractable at 1 CPU, do not silently weaken the task.
Follow the fallback your slot names, or keep the same repository and change what
the agent does with it (navigate and patch, compiling only the changed sources
against a classpath you captured at build time), and record the substitution in
`difficulty.json` notes and in your report.

## The verifier asserts on the real project

The point of the family is that the project is real, so the verifier must use
the project's own machinery rather than a paraphrase of it:

- run the project's own test runner on targeted tests,
- execute the binary the agent built, not a reference binary you shipped,
- import the library the agent installed, not a stub,
- compare against an independently computed expectation where one exists.

Keep the usual requirements: at least two hidden cases that genuinely differ,
every declared deliverable executed, binary reward, reward on every exit path,
and a nop score of 0.

One thing that is easier to get wrong here than elsewhere. A task whose agent
could pass by ignoring the upstream tree entirely is not an upstream task. If
the deliverable can be satisfied by writing a fresh self-contained script that
never touches the clone, tighten it: require the project's own binary, or its own
test suite to pass, or an import from the installed package, and assert that.

## Acceptance

Same gate as before, plus the new one:

```bash
cd /home/ee/pi-setup/evals/general
python3 tools/check_upstream_disjointness.py     # must be 0 problems
bash tools/verify_new_task.sh <name>             # must exit 0: oracle 1, nop 0
```

Report the upstream repository, the exact 40-hex commit you pinned, the measured
image build time, the measured image size, and how you confirmed the trial runs
with no network.

## Image size budget (added after the v4.3 waves produced 20-32 GB images)

Aim under 6 GB. Hard limit 12 GB. `tools/check_image_size_hygiene.py` enforces the
cause statically and reports measured sizes where an image exists locally.

Nothing else catches an oversized image. `storage_mb` in task.toml is advisory in
harbor 0.22.0: it is parsed, carried into telemetry and mapped for terminal-bench
format, but there is no `storage_opt` or `--storage-opt` anywhere in harbor, so it
is never passed to docker as a limit. A 30 GB task image passes every gate and
still makes the suite undistributable.

### The one habit that causes most of it

Docker layers are copy-on-write. `RUN chown -R 1000:1000 /app/src` in its own layer,
after a `RUN make` filled `/app/src`, writes a second copy of every file into a new
layer. Measured on this host with a 400 MB blob: the image went from 1.07 GB to
1.49 GB, exactly the blob size. In `tasks/gunwale-tideway`, which builds git from
source, `docker history` shows two layers of exactly 2.74 GB each, because line 38
runs `make -j1` and line 58 chowns the tree in a separate RUN. Half of that 6.73 GB
image is the same bytes stored twice.

Three ways to avoid it, in order of preference:

1. Create the tree with the right ownership in the first place. `git init` and the
   build as the user that will own it, or `install -d -o 1000 -g 1000` before
   anything writes into it.
2. Put the ownership change in the SAME `RUN` as the build that produced the files.
   A layer is written once, so a chown at the end of the build RUN costs nothing.
3. `COPY --chown=1000:1000` for anything you copy in.

The same applies to `chmod -R a+rwX /opt/cargo` after installing a Rust toolchain:
the toolchain plus the registry cache is copied a second time.

### The rest

- `rustup toolchain install --profile minimal` unless the task genuinely needs
  clippy, rustfmt or the docs. The default profile pulls all three.
- Delete build byproducts the trial does not need, in the same RUN that made them:
  `target/` for Rust, `_build` for meson, `node_modules/.cache`, `__pycache__`,
  `*.o` if the task does not relink. If the agent DOES need incremental relinking,
  keep them, but then never chown them in a later layer.
- Use a multi-stage build when the task only needs the resulting binary: compile in
  a builder stage, copy the artifact into a slim final stage. This is the single
  biggest reduction available for a C, C++ or Rust project.
- `--no-install-recommends` on apt, and `rm -rf /var/lib/apt/lists/*` in the same
  RUN. Most tasks already do this.
- Do not install a full toolchain when the project ships a prebuilt release the task
  could use instead, unless building from source IS the task.

### Check before you finish

```bash
docker build -t <name>-size tasks/<name>/environment
docker system df -v | grep <name>          # UNIQUE SIZE is the honest number
docker history --format '{{.Size}}\t{{.CreatedBy}}' <name>-size | head -15
```

`docker images` reports total size including layers shared with other images, so it
overstates what your task costs and understates what removing it frees. `docker
system df -v` gives unique size. If `docker history` shows two layers of the same
size, that is the duplication pattern above.
