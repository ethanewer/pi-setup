# `fd` dies with a panic when the directory it was launched from disappears mid-search

## Situation

`/app/src` is a shallow, pinned clone of `fd` (`https://github.com/sharkdp/fd`), a
fast, user-friendly alternative to `find`, checked out at upstream commit
`7027d45303b412be6fa9c09d689cc6276748fb38` (fd 10.4.2). The Rust toolchain
(1.98.1) and every dependency the project needs are already installed and
cached, and the project has been built once so your subsequent builds are
incremental. The trial has **no network**: `git fetch`, `rustup`, and `cargo`
downloads will not work; everything needed is baked into the image and the
environment variable `CARGO_NETWORK=off` is set to make that explicit.

## The bug

Suppose a search is launched from some directory, and while the search is still
running, that directory is *removed* (for example a build script or a temporary
directory wrapper that is cleaned up out from under the running search). When
the search uses `--full-path` (search and match against the full absolute
paths of files), the program dies with an unhandled panic instead of finishing,
skipping, or reporting the problem:

```
$ fd --full-path . link   # launched from a directory that is removed mid-search
thread '<unnamed>' panicked at src/walk.rs:529:26:
Retrieving absolute path succeeds: Os { code: 2, kind: NotFound, message: No such file or directory }
```

The process then exits with status 101 (a Rust panic). The crash happens per
matched file: while `--full-path` is active, the program tries to resolve the
process's current directory for every match, hits the "not found" result, and
aborts the whole search. Note that launching from a directory that was
*already gone at startup* is handled gracefully — it is the directory being
removed *while the search is running* that kills the run.

## Reproducing the failure

Everything you need is in the image:

```
cd /app/src && cargo build
/app/probe_cwd_removed.sh
```

`/app/probe_cwd_removed.sh` rebuilds the scenario deterministically: it creates
a large tree of plain files, launches `fd --full-path` from a working directory
containing only a symlink to that tree, and deletes the working directory
roughly 0.2 seconds after fd starts, then reports whether the crash is present.
While the bug is present it prints the panic and exits with status 1. (The tree
it builds is large on purpose: the walk must outlast the deletion for the race
to fire. You can size it with the `FD_PROBE_N` environment variable.)

The project's own test suite (`cargo test` from `/app/src`) is green at this
checkout; the upstream regression test for this behaviour was added in the same
upstream change that fixed the bug, so it is **not** part of this checkout.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that a search whose working
directory is removed mid-search no longer panics. The program should instead
finish, skip, or report the problem gracefully — in particular it must not die
with a Rust panic (exit 101). The exact graceful behaviour is your choice as
long as the process does not abort: the upstream project chose to abort the
search and report the filesystem error (exiting with status 1 under
`--show-errors`), and the verifier accepts that, but a fix that finishes the
search normally is also acceptable. What must keep working:

- `--full-path` searches from a normal, always-present working directory
  behave exactly as before (all matches found, exit 0);
- searches without `--full-path` are completely unaffected (they never touch
  the current-directory resolution);
- `--exec` (`-x`) and `--exec-batch` (`-X`) searches with `--full-path` must
  not panic either — they see the same crash path, and the fix must cover
  them;
- the rest of the project's test suite stays green.

Drive your work with the project's own tooling from `/app/src`:

- `cargo build` builds the `fd` binary (`target/debug/fd`);
- `cargo test` runs the project's unit and integration test suites, both of
  which are self-contained and need no network.

The whole project test suite is green at the pinned commit; keep it green. One
caveat: the integration test `test_exec_nulls` (it exercises `--exec` output
interleaving, unrelated to working-directory handling) is timing-sensitive and
can fail spuriously inside the trial container, which is capped at 1 CPU — it
fails there even on a pristine tree or on a fully correct fix, and it passes on
a multi-core machine. The verifier runs the suite with exactly that one test
skipped. If you see that test fail, ignore it; any other failure is a real
regression.

## Constraints

- Network is unavailable; everything needed is already installed.
- The clone at `/app/src` is the deliverable. Change only what the fix
  requires, in place, and only tracked source files under `src/`. Do not
  rewrite history, commit, add remotes, fetch, change build files, modify or
  delete the project's own tests, or add new files under `src/`.
- Do not touch the harness-owned directories `/opt/golden`, `/tests`, and
  `/solution`.
- The verifier checks that the working tree is still at the pinned commit
  `7027d45303b412be6fa9c09d689cc6276748fb38`, that the clone still contains
  exactly that one commit (no history was fetched or added, nothing was
  committed), that no tracked file was deleted, that the only modified tracked
  files are the project's own source files under `src/` (at least one such
  modification is present), and that no new files were added under `src/`.

## What the verifier checks

1. Tree provenance as listed above (stale or unfetched state scores 0).
2. `cargo build` of the repaired tree must succeed.
3. The upstream regression test for this behaviour is run against your tree
   when the tree can accept it (a fix shaped like the upstream one carries it);
   the behavioural contract is checked in every case by the steps below.
4. The project's own full test suite still passes (unit + integration, with
   the timing-sensitive `test_exec_nulls` skipped for the 1-CPU reason above).
5. Hidden CLI cases exercising the same code path from inputs the upstream
   regression test does not use: a `--full-path` search whose working
   directory is removed mid-search in (a) the default print mode, (b) `-x`
   exec mode, and (c) `-X` exec-batch mode. Each runs with `--show-errors` and
   must exit with status 1 (no panic), print no panic message, and report the
   filesystem error ("No such file or directory").

Deliverable: the repaired `/app/src` tree.