# cringle-barquentine

You are working inside a real, widely-used open-source codebase: **ripgrep**
(`BurntSushi/ripgrep` — the `rg` command-line recursive search tool), checked
out at a pinned historical commit in `/app/src` (detached HEAD, clean working
tree, warm release build already done). There is a bug in this tree's
**word-matching** search machinery. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You are
deliberately **not** told which file or function to change: localising the bug
is part of the task.

## Environment

- The full repository lives at `/app/src` (Rust workspace: the `rg` binary plus
  several `crates/*` workspace members). The tree is detached at the pinned
  commit and must stay there — **do not commit, fetch, push, rebase, stash,
  apply any downloaded patch, or otherwise modify `.git`**.
- The release build is **warm**: `cargo build --release` already ran at image
  build time, and the binary is `/app/src/target/release/rg`. `cargo` is
  incremental, so after you edit a crate only that crate recompiles (with
  `cpus = 1`, a full clean rebuild takes about a minute).
- The Rust toolchain (rustc/cargo **1.98.1**) is installed at `/opt/rust/bin`
  and already on `PATH`; `CARGO_HOME=/opt/rust` holds a warm dependency cache.
  The project's committed `Cargo.lock` pins every dependency version — do not
  run `cargo update` and do not edit `Cargo.lock`.
- **There is no network** in this container. Everything you need is baked in.
  Treat the container as offline.
- `cpus = 1`: one vCPU for the whole container; build with `-j1`.

## The bug (user-visible symptom)

`rg -w/--word-regexp` restricts matches to whole words. Combined with
`-o/--only-matching` and `-n/--line-number`, it is a standard way to list every
word-boundary match position in a file.

On this tree, there is a class of inputs that makes the tool **crash partway
through its own output**: the search prints some of the match positions, then
aborts with an internal assertion failure and a non-zero exit code, instead of
reporting all of the word-boundary match positions. The crash happens in the
**release** build too (not only in a debug build).

The trigger is a pattern that can match the **empty string**. The empty
pattern `''` is the simplest example, but the same failure is reachable with
other empty-matchable patterns such as `x?`, `t?`, `^`, or `[:space:]*`.
When the command aborts, `stderr` shows an internal panic of the form
`assertion failed: self.start <= end` pointing into a matcher crate.

A correctly fixed tree must make such a command **exit 0 and report every
word-boundary match position** for the input — never panic, never truncate the
output mid-run.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — your own minimal reproduction of the symptom above.
   You must find the failing input yourself: pick a small file whose shape
   trips the bug and one of the empty-matchable patterns above, and verify
   that the release binary aborts on it. Its contract:

   - It must honour an environment variable `RG_BIN` naming the `rg` binary to
     execute, defaulting to `/app/src/target/release/rg` when unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`: it
     creates exactly one small input file (the one that trips the bug) with
     contents of your choosing, then runs the affected command exactly —
     `"$RG_BIN" -won <pattern> <file>` with the `-w -o -n` flags combined
     exactly so, and no extra flags — from inside that scratch directory.
   - It prints exactly what `rg` prints (stdout and stderr), and nothing else.
   - It exits 0 if and only if the command exited 0 **and** its stdout
     contained the complete list of word-boundary match positions for that
     input (every one of them — nothing truncated at the crash point);
     otherwise it exits non-zero.
   - It must work no matter what the current working directory is when it is
     invoked, and it must not touch anything outside its scratch directory.

   On the **unfixed** tree this script must fail: the command panics mid-run,
   its exit code is non-zero and its output is incomplete. Confirm that now,
   before fixing anything. (A reproduction that does not actually fail on the
   unfixed tree proves nothing — the graded checks run it against a pristine
   unfixed binary and require it to fail there.)

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, complete output), and keeps passing after a
   rebuild with `cargo build --release -j1`. Fix the mechanism, not just one
   input: the same defect is reachable with the other empty-matchable patterns
   (`x?`, `t?`, `^`, `[:space:]*`, ...) and other input layouts — the graded
   checks exercise those directly through the built binary. Do not merely
   special-case a pattern or an input in a wrapper script or in the CLI layer;
   the graded checks run the real binary on the real code path.

3. **Break nothing else.** Everything else must keep working exactly as
   before: ordinary word matching (`-w` with non-empty patterns),
   non-word matching, `-o` without `-w`, multi-line searches, and the rest of
   `rg`'s behaviour. The project's own test suites must stay green (see
   below).

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate
   (including core dumps from the crashing binary), delete them before you
   finish; make no commits; do not touch `tests/`, `Cargo.lock`, `Cargo.toml`
   or any other file. The grader compares every file's bytes against the
   pinned commit's own blobs, so cosmetic side-changes also fail. Your two
   authored files `/app/repro.sh` and `/app/summary.md` live **outside**
   `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/target/release/rg`. Try `-w -o -n` with an
   empty-matchable pattern against a few small hand-made inputs, and find one
   input shape that makes the command abort partway through its output; record
   the exit code and the truncated stdout and the panic line in stderr. Try
   the sibling invocations — the same pattern **without** `-o`, the same file
   **without** `-w` — to pin down precisely which flag combination aborts and
   which ones are fine.
2. **Localise** the bug by reading the code. Trace what `-w` does to the
   pattern before it is compiled, what `-o` requires of each match, where a
   match range could come out inverted (start after end), and why an
   empty-matchable pattern makes that happen. Understand *why* the assertion
   fires before you patch.
3. **Fix** with the smallest possible change in that one source file, rebuild
   (`cargo build --release -j1`), and confirm `/app/repro.sh` passes against
   the rebuilt binary.
4. **Prove nothing else broke**: run the project's own integration test suite
   from `/app/src` with `cargo test --release -j1` (all tests must pass; at
   this commit that is 271 integration tests), and the unit tests of the two
   search-related crates with
   `cargo test --release -j1 -p grep-regex -p grep-matcher`. A crashy binary
   aborting mid-suite will show up there as a failed test.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned commit, that the upstream fix commit
  is **not** reachable from this clone, and that every tracked file except the
  single source file the bug lives in is byte-identical to that commit (any
  other modification, added file or untracked scratch file fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  behave per their contracts;
- force a clean rebuild from your tree (`cargo clean` then
  `cargo build --release -j1`) and run your `/app/repro.sh` against that
  repaired binary (it must pass) **and** against a pristine pre-fix `rg`
  binary baked into the image at `/opt/prefix/rg` (it must fail — proving the
  symptom is real and your reproduction targets it);
- plant the project's **own regression test** for this defect — upstream added
  it in the commit that fixed this bug, so it does not exist in this tree —
  into the tree's test suite, require that test to pass, and require the full
  existing integration suite plus the two crates' unit test suites to stay
  green;
- run hidden cases that reach the same code path from other empty-matchable
  patterns and other input layouts (inputs the upstream regression test does
  not use), each run against the rebuilt binary and required to produce the
  exact correct output.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.