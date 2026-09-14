# gunwale-tideway

You are working inside a real open-source codebase: **git** (the version
control system, `git/git`), checked out at a pinned historical commit in
`/app/src` (the working tree starts clean and fully built). There is a bug in
this tree's multi-remote fetch machinery. Your job is to find it, fix it in
the working tree, and prove the fix with the project's own test tooling. You
are deliberately **not** told which file or function to change: localising
the bug is part of the task.

## Environment

- `git` is built from this very tree at `/app/src`; the build is **warm**
  (a full `make -j1` already ran at image build time, so your rebuilds after
  edits are incremental and take seconds). The built binary is
  `/app/src/git`.
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, push, rebase or otherwise modify `.git`** — the working tree is
  detached at the pinned commit and must stay there.
- **There is no network** in this container. Everything needed is baked in.
- `cpus = 1`: one vCPU. A full clean rebuild takes about two minutes; prefer
  incremental `make -j1` builds.
- The project's own regression-test suite lives in `/app/src/t/` (each
  `t/tNNNN-*.sh` is a self-contained shell test script). The tests use only
  local repositories and never touch the network.
- `git`'s test scripts set up their own home directory, config and identity,
  so config you may have in your environment does not affect them.

## The bug (user-visible symptom)

`git fetch --multiple` fetches from several remotes at once. The command
accepts a `--jobs=<n>` option to set how many fetches run in parallel, and it
honours a matching configuration setting. The documented contract for a
parallel-fetch setting of **0** is that git picks a sensible default (the
number of processors), and that is what both the option and the setting have
done historically.

On this tree, however, there is a specific way to invoke the command that
does not do that: **passing `--jobs=0` explicitly**. In that case the
command aborts its own run before fetching anything. It prints an internal
BUG diagnostic into stderr, something like

```
BUG: run-command.c:NNNN: you must provide a non-zero number of processes!
```

and then dies by signal (abort), with a non-zero exit status. The remotes
are never contacted and nothing is fetched. The very same command with
`--jobs=1` (or without `--jobs`, or with the equivalent configuration
setting set to 0) works fine.

The affected behaviour is a parallel multi-remote fetch started with
`--jobs=0`: such a command must succeed, fetch from every remote, and exit 0
— using the default parallel count — not abort with a BUG diagnostic.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `GIT_BIN` naming the git binary
     to execute, defaulting to `/app/src/git` when unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`:
     two or more bare repositories, each containing at least one branch, and
     one empty non-bare repository that has all of them added as remotes.
   - It must then run the affected command exactly -- the parallel
     multi-remote fetch with `--jobs=0`, with the two remotes passed as
     command-line arguments (e.g. `"$GIT_BIN" fetch --multiple
     --jobs=0 one two`, run from inside the empty repository, with no
     extra repository configuration). Naming the remotes as arguments is
     what gives the command something concrete to fetch, so that after a
     real fix the fetched refs are observable.
   - It prints everything git prints (stdout and stderr), and nothing else.
   - It exits 0 if and only if the command exited 0 **and** every named
     remote's branch actually arrived (each remote-tracking ref exists
     after the fetch); it exits non-zero (printing git's output, which
     will show the crash) otherwise.
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory.

   On the **unfixed** tree this script must fail: the command aborts with
   the BUG diagnostic, so it exits non-zero and the refs are missing.
   Confirm that now, before fixing anything.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0, every remote's ref present), also after
   a fresh `make -j1`. Fix the mechanism, not just one input: the same
   defect is reachable with any number of remotes, with some remotes
   unreachable, with `--tags`, and with repeated fetches against the same
   remotes (see Grading). Do not merely special-case your reproduction in a
   wrapper script — the graded checks exercise the code path directly
   through the built binary.

3. **Break nothing else.** Everything else must keep working exactly as
   before: plain single-remote `git fetch` and `git pull` with default
   parallelism, `--jobs=<n>` with positive counts, and the parallel
   multi-remote machinery with the configuration-default parallelism. The
   project's own test suite must stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate
   (including core dumps from the crashing binary), delete them before you
   finish; make no commits; do not modify `t/`, `Makefile`, or any other
   file. The grader compares every file's bytes against the pinned commit's
   own blobs, so cosmetic side-changes also fail. Your two authored files
   `/app/repro.sh` and `/app/summary.md` live **outside** `/app/src` and are
   fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src/git` exactly as described (scratch files in
   `/tmp`, never inside `/app/src`): a couple of bare remotes, an empty
   repo with both remotes added, then the affected command. Observe the BUG
   diagnostic and the abort. Try the sibling invocations (`--jobs=1`, no
   `--jobs`, the same parallelism choice expressed through configuration) to
   pin down precisely which input shape aborts.
2. **Localise** the bug by reading the code. Trace where the option's value
   ends up, what the code does with an explicit 0, and where the parallel
   machinery enforces a non-zero process count. Understand *why* the
   explicit `0` reaches the machinery while the default path does not before
   you patch.
3. **Fix** with the smallest possible change in that one source file,
   rebuild (`make -j1`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own fetch and pull test
   suites from `/app/src/t/`, for example `./t5514-fetch-multiple.sh` and
   `./t5510-fetch.sh` and `./t5520-pull.sh` (each prints
   `# passed all N test(s)` when green). A crashy binary aborting mid-suite
   will show up there as a failed test.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.sh` — your own failing reproduction, per the contract above.
3. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.sh` and `/app/summary.md` to exist, be non-empty and
  behave per their contracts;
- force a clean rebuild from your tree (`make clean` + `make -j1`) and run
  your `/app/repro.sh` against that repaired binary (it must pass) **and**
  against a pristine pre-fix `git` binary baked into the image at
  `/opt/prefix/git` (it must fail — proving the symptom is real and your
  reproduction targets it);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it with the fix, so it does not
  exist in this tree) into `t/t5514-fetch-multiple.sh`, run the whole
  `t5514` suite, and require the new test and all previous tests to pass;
- run a selection of the project's existing fetch/pull suites
  (`t5510-fetch.sh`, `t5513-fetch-track.sh`, `t5520-pull.sh`) and require them to pass;
- run authored hidden CLI cases exercising the same code path from inputs
  the upstream regression test does not use (more remotes, `--tags`,
  changed branch tips between fetches, an unreachable remote alongside a
  reachable one), each run against the rebuilt binary.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.