# capstan-caboose

You are working inside a real upstream open-source project: **starship** — the
cross-shell prompt — checked out at a pinned commit in `/app/src` (the working
tree starts clean). There is a bug in this tree's prompt-module logic. Your job
is to find it, fix it in the working tree, and prove the fix with the project's
own test tooling. You are deliberately **not** told which file, function or
module to change: localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency; always build with
  `--locked`.
- **No outbound network.** Everything needed is baked in: the crates.io
  dependency cache and a warm `target/` build directory (all dependencies, the
  `starship` debug binary and the unit-test harness were compiled at image
  build time). Any `cargo` command completes offline; cargo is configured to
  fail closed rather than wait on the network.
- `cpus = 1`: one vCPU. Do not launch parallel builds; cargo will use the
  single core. An incremental rebuild after a one-file edit takes a few
  minutes — budget for it.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.

## The bug (user-visible symptom)

Render the prompt inside a directory that merely **contains a `.mvn` folder**
but no actual Maven project — for example a user-level Maven configuration
directory holding only `.mvn/maven.config`, with no `pom.xml` and no Maven
wrapper properties anywhere:

```
mkdir -p /tmp/proj/.mvn
touch /tmp/proj/.mvn/maven.config
printf 'format = "$maven"\nadd_newline = false\n[maven]\ndisabled = false\n' > /tmp/mvn.cfg
STARSHIP_CONFIG=/tmp/mvn.cfg /app/src/target/debug/starship prompt --path /tmp/proj
```

The bug: that command prints the maven module — an empty `via` version tag
with the maven symbol — even though the directory is not a Maven project at
all. The maven segment must only appear for real Maven projects: directories
containing a `pom.xml`, or a Maven wrapper properties file
(`.mvn/wrapper/maven-wrapper.properties`). A bare `.mvn` folder (or any
other unrelated folder or dotfile) must never activate it.

## Requirements

1. Fix the tree so that `starship prompt` (and the underlying module) shows
   the maven segment **only** when a real Maven project marker is present:
   a `pom.xml`, or `.mvn/wrapper/maven-wrapper.properties`.
2. Everything else must keep working exactly as before: real Maven project
   directories (those to which the module currently responds, including the
   wrapper-properties case) must still render the maven segment, with the
   version read from `maven-wrapper.properties` (e.g. `via 🅼 v3.9.12`) when
   one exists. Do not change the accepted semantics of any other directory.
3. The graded tree must be byte-identical to the original except for the
   source changes the fix requires. Do not add, move, delete, rename or
   reformat any file; if you create scratch files to investigate, delete them
   before you finish; make no commits. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the CLI command above (the debug binary is already
   built; no compilation needed). Confirm the bogus maven segment appears in
   the `.mvn`-only directory, and that a control directory (e.g. empty, or
   containing an unrelated file) does not.
2. **Study the module's detection logic** in the source tree: every prompt
   module lives under `src/modules/`, with its default detection configuration
   under `src/configs/` — grepping for `maven`, `detect_folders`,
   `detect_files` and `maven-wrapper` will find the pieces.
3. **Fix** the detection, then rebuild incrementally and re-check both
   directions: the `.mvn`-only directory must no longer render the segment
   (`STARSHIP_CONFIG=/tmp/mvn.cfg ./target/debug/starship prompt --path /tmp/proj`
   prints nothing), while a directory with a `pom.xml` and one with
   `.mvn/wrapper/maven-wrapper.properties` still do.
4. **Run the project's own maven-module unit tests** (warm, offline):
   `cd /app/src && cargo test --locked --offline -- maven`
   All tests matching the `maven` module (the project's inline unit tests for
   it) must pass on your fixed tree.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit and that every tracked
  file except the maven-module source surface is byte-identical to that commit
  (any modification elsewhere, any added file or untracked scratch file
  fails);
- require `/app/summary.md`;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`, from a successor revision of the tree) plus its own
  hidden cases into the maven module's test block, rebuild the unit-test
  harness offline, and run the maven-module tests. Every maven-module test
  must pass: the regression test, hidden variants over project layouts the
  upstream test does not use (`pom.xml`-only directories, wrapper-properties
  directories, and a `.mvn` directory holding a non-wrapper file), and the
  project's own pre-existing maven tests.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.