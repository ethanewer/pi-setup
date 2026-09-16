# alewife-anchorage

You are working inside a real open-source codebase: **ripgrep**
(`BurntSushi/ripgrep`), a line-oriented text search tool, checked out at a
pinned commit in `/app/src` (the working tree starts clean). There is a bug
in this tree's ignore-file / hidden-file machinery. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- Rust toolchain 1.98.1 is installed and on `PATH` (`cargo`, `rustc`, `git`).
  The repository's `Cargo.lock` pins every crate dependency — do **not**
  run `cargo update` or change the lockfile.
- **There is no network** in this container. Everything needed is baked in:
  the crates.io dependency cache and a warm `target/` build directory (the
  whole workspace, the `rg` debug binary and the test harness were compiled
  at image build time at this same commit). Any `cargo` command you run
  completes offline.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`.
- `/app/src/target/debug/rg` is the debug binary built from this tree.

## The bug (user-visible symptom)

ripgrep skips hidden files (anything whose name starts with `.`) unless they
are explicitly re-included. The normal way to re-include one is a *whitelist*
rule — a `!`-negation in an ignore file, for example a line like `!.foo.txt`
in a `.ignore` file — and ripgrep documents that negated rules re-include
otherwise-hidden files.

But there is a way to invoke ripgrep where that re-inclusion silently stops
working. If the search starts **inside a subdirectory** — not at the
directory where the ignore file lives — and the search path is spelled as
**`.`**, ripgrep reports **no files at all** for that subdirectory even
though it contains a whitelisted hidden file that should be listed. The very
same search run from the parent directory works, and the very same search
run from the same subdirectory with the search path spelled any other way
(either by not giving a path at all, or by writing `./`) lists the file
correctly. So: hidden files explicitly whitelisted with `!` are still
skipped, but only for that one path spelling, while the tool otherwise
works fine.

The affected behaviour is the file listing (`--files`): a whitelisted hidden
file inside such a subdirectory must appear in the output, and the command
must exit 0. Instead, on this tree, it prints nothing and exits 1 (ripgrep
exits 1 when nothing is searched/found).

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `RG_BIN` naming the ripgrep
     binary to execute, defaulting to `/app/src/target/debug/rg` when
     unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`,
     including a subdirectory containing a hidden file and an ignore file
     with a whitelist rule that re-includes it, and run ripgrep's `--files`
     with the affected path spelling from inside that subdirectory.
   - It prints everything ripgrep prints, and nothing else.
   - It exits 0 if and only if the whitelisted hidden file appears in the
     command's output; it exits nonzero (and prints ripgrep's output, which
     will be empty) otherwise.
   - It must work no matter what the current working directory is when it
     is invoked.

   On the **unfixed** tree this script must fail: the whitelisted hidden
   file is silently skipped, so it exits nonzero with no listing. Confirm
   that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, whitelisted hidden file listed), also
   after a fresh `cargo build`. Fix the mechanism, not just one input: the
   same defect is reachable with other hidden file names, other whitelist
   patterns (for example `!.*` or a glob), deeper directory nesting, and
   hidden directories (see Grading). Do not merely special-case the
   invocation in a wrapper script — the regression test the grader runs
   exercises the code path directly through ripgrep's own machinery.

3. **Break nothing else.** Everything else must keep working exactly as
   before: listing files with or without a path argument, from any
   directory, and at any depth; plain search; `.ignore` / `.gitignore`
   handling with plain ignore rules; command-line ignore flags
   (`--no-ignore`, `--no-ignore-dot`, `--no-ignore-exclude`, `--ignore-file`,
   `--no-ignore-vcs`). The project's existing test suite must stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `Cargo.toml`, `Cargo.lock` or any metadata file. The grader compares
   every file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail. Your two authored files `/app/repro.sh` and
   `/app/summary.md` live **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/target/debug/rg` (scratch files in `/tmp`,
   never inside `/app/src`). Study which of the six natural invocation
   forms work and which one fails before you touch any code, so your
   reproduction is precise.
2. **Localise** the bug by reading the code: trace how ignore files are
   collected and how a file's path is rewritten while ignore rules are being
   applied, paying attention to where a leading `.` or `./` in a path could
   be altered on the way to the matcher. Understand *why* only the `.`
   spelling is affected before you patch.
3. **Fix** with the smallest possible change in that one source file,
   rebuild (`cargo build`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: the project's own test harness lives in
   `tests/` and is compiled with `cargo test --no-run`; the resulting
   executable is `target/debug/deps/integration-*` (new cargo layout places
   test binaries under `target/debug/deps/`). Run a targeted subset by
   passing plain filter arguments, e.g.
   `"$(ls -t target/debug/deps/integration-* | grep -v '\.d$' | head -1)" r2711 r829_original r829_2731 r829_2778 f1138_no_ignore_dot f1420_no_ignore_exclude`
   — every one of these passes on the pristine tree and must still pass
   after your fix.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/repro.sh` and `/app/summary.md` to exist and be non-empty;
- rebuild the debug `rg` from your tree, then run your `/app/repro.sh`
  against that repaired binary (it must pass) **and** against a pristine
  pre-fix `rg` binary baked into the image at `/opt/prefix/rg` (it must
  fail — proving the symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into `tests/regression.rs`, rebuild the harness
  offline, and run it: the planted regression test must pass, and a
  selection of the project's existing ignore/whitelist integration tests
  must still pass;
- run `target/debug/rg` directly on **hidden CLI cases** — other hidden
  names, other whitelist patterns, deeper nesting, and hidden directories
  that reach the same broken code path — each must print the expected
  listing with exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.