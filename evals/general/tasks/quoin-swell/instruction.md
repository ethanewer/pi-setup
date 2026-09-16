# quoin-swell

You are working inside a real open-source codebase: **fd** (the file-finder
`sharkdp/fd`, written in Rust), checked out at a pinned historical commit in
`/app/src` (the working tree starts clean and fully built). There is a bug in
how this tree handles one particular search-path argument. Your job is to find
it, fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- **fd** is built from this very tree at `/app/src`. The build is **warm**: a
  full `cargo build -j1` (debug profile, binary at `/app/src/target/debug/fd`)
  already ran at image build time, and the integration-test harness is
  pre-compiled, so your rebuilds and test runs after edits are incremental and
  take seconds, not minutes.
- The Rust toolchain lives in `/opt` (cargo, rustc and the dependency cache).
  **`CARGO_NET_OFFLINE=true` is set for the whole session**: cargo is forced
  fully offline, and everything it needs is already in the image. Do not
  change that variable; if cargo reports a missing crate, you have asked for
  something the image does not contain.
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, push, rebase, graft or otherwise modify `.git`** — the working tree is
  detached at the pinned commit and must stay there.
- **There is no network** in this container. Everything needed is baked in.
  `cpus = 1`: one vCPU. Prefer `cargo build -j1` (the default job count is 1
  anyway).
- Read `/app/README-BUILD.md` for what is baked where.

## The bug (user-visible symptom)

A user reports:

> I script searches against a set of directories. One directory's name is a
> single dash, `-`, literally. When I point the tool at that directory using
> the name on its own, it silently returns **nothing at all** — no files, no
> error, exit status 0. If I reference the same directory with an explicit
> `./` prefix it works perfectly. The result depends only on how the
> directory argument is spelled, not on the directory itself. My wrapper
> scripts pass directory names from variables, so this silent empty result is
> costing me real search misses.

Reproduce the report precisely before you change anything:

```
$ cd /tmp/somewhere
$ mkdir -p -/via_explicit_dash_dir ...   # a real directory whose name is "-"
$ ls -/...
$ fd . -            # silently prints NOTHING, exits 0
$ fd . ./-          # prints the same directory's contents correctly
```

The affected behaviour is: **a search path argument equal to `-`** (as passed
to the tool's search-path argument, whether spelled as the positional
search path or via its long option) **must search the real directory named
`-` in the current working directory and must return what is in it**, instead
of silently matching nothing.

## Your job

1. **Write a failing reproduction first.** Before you change any source code,
   write `/app/repro.sh` — your own minimal reproduction of the symptom
   described above. Its contract:

   - It must honour an environment variable `FD_BIN` naming the fd binary to
     execute, defaulting to `/app/src/target/debug/fd` when unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`:
     one real subdirectory whose name is exactly `-` (create it with
     `mkdir -p "$work/-"` and put at least one file inside it, e.g.
     `foo.txt`).
   - It must then `cd` into the scratch directory and run the affected
     command exactly: `"$FD_BIN" . -` — pattern `.`, search path `-`, no
     other options, stdout and stderr captured.
   - It prints everything fd prints (stdout and stderr), and nothing else.
   - It exits 0 if and only if the command exited 0 **and** the captured
     output contains the entry fd returns for the file inside the `-`
     directory (`./-/foo.txt`); it exits non-zero (printing fd's output,
     which is empty on the unfixed tree) otherwise.
   - It must work no matter what the current working directory is when it is
     invoked, and it must not touch anything outside its scratch directory.

   On the **unfixed** tree this script must fail: the command exits 0 but
   prints nothing, so your script exits non-zero. Confirm that now — before
   fixing anything.

2. **Fix the tree.** Make the smallest possible change so that `/app/repro.sh`
   passes (exit 0, the `./-/foo.txt` entry present), also after a fresh
   `cargo build -j1`. Fix the mechanism, not just one input: the same defect
   is reachable when the dash-named directory is nested, when a pattern (not
   just `.`) is searched, when the dash path is one of several search paths,
   and when the path comes from the long option form (see Grading). Do not
   merely special-case your reproduction in a wrapper script — the graded
   checks exercise the code path directly through the built binary.

3. **Break nothing else.** Everything else must keep working exactly as
   before: ordinary searches, absolute paths (`--absolute-path`), the `.`
   root's existing behaviour, `--search-path` with normal directory names,
   and the project's own test suite. One caveat about the suite: in this
   1-CPU sandbox the project's integration test `test_exec_nulls` is known to
   fail even on a pristine tree (its expectation depends on the command-exec
   pool width, not on this bug); the graded run skips exactly that one test.
   Do not be chased by it, do not "fix" it — every other test must pass.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `Cargo.*`, `Makefile`, or any other file. The grader compares every file's
   bytes against the pinned commit's own blobs, so cosmetic side-changes also
   fail. Your two authored files `/app/repro.sh` and `/app/summary.md` live
   **outside** `/app/src` and are fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was, what
   you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/target/debug/fd` exactly as described (scratch
   files in `/tmp`, never inside `/app/src`): a scratch dir containing a real
   `-` subdirectory with a file in it, then run `fd . -` and `fd . ./-`.
   Observe the silent empty output and the exit status. Try sibling spellings
   (the long option form; the dash path alongside another valid path) to pin
   down precisely which input shape is affected.
2. **Localise** the bug by reading the code. Trace where search-path
   arguments are turned into the base paths handed to the walker, and
   understand *why* a bare `-` is treated differently from `./-` before you
   patch. The fix is a few lines in exactly one place — finding that place is
   the point.
3. **Fix** with the smallest change in that one source file, rebuild
   (`cargo build -j1`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own test suite with
   `cargo test -j1 -- --skip test_exec_nulls` from `/app/src` (it prints
   `test result: ok. ... N passed; 0 failed ...` when green). Everything
   except the skipped test must pass.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is **not** reachable from this clone, and that every tracked file
  except the single source file the bug lives in is byte-identical to that
  commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty,
  executable, and behave per their contracts;
- force its own rebuild of the tree (`touch` + `cargo build -j1`, offline) and
  run your `/app/repro.sh` against that rebuilt binary (it must pass) **and**
  against a pristine pre-fix `fd` binary baked into the image at
  `/opt/prefix/fd` (it must fail — proving the symptom is real and your
  reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden/tests.rs` — upstream added it with the fix, so it does
  not exist in this tree), run the whole suite once (with only the known
  `test_exec_nulls` exception skipped), and require the new regression test
  and all other tests to pass;
- run authored hidden cases exercising the same code path from inputs the
  upstream regression test does not use — a nested dash-named directory, a
  filtered pattern, the dash path alongside other search paths, and the long
  option form — each against both the rebuilt binary (must pass) and the
  pristine pre-fix binary (must fail).

Reward is binary: 1 if and only if all of the above hold, otherwise 0.