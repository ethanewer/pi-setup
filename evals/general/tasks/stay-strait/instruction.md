# stay-strait

You are working inside a real open-source codebase: **git** (the version
control system, `git/git`), checked out at a pinned historical commit in
`/app/src` (the working tree starts clean and fully built). There is a bug
in this tree's local-clone machinery. Your job is to find it, fix it in the
working tree, and prove the fix with the project's own test tooling. You
are deliberately **not** told which file or function to change: localising
the bug is part of the task.

## Environment

- `git` is built from this very tree at `/app/src`; the build is **warm**
  (a full `make -j1` already ran at image build time, so your rebuilds after
  edits are incremental and take seconds). The built binary is
  `/app/src/git`. Use *that* binary and its build tree for everything in
  this task — a different `git` on your `PATH` is a different version and
  will not show the bug.
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

`git clone` can clone a repository straight from a local path on disk
(e.g. `git clone /some/path/to/repo new-copy`). This is a completely
ordinary operation, and cloning any local repository with well-formed refs
works fine.

There is a specific kind of input that makes this tree's clone command
crash: when the **source** repository contains a ref file whose contents
are not a valid object id — for example a ref file under its
`.git/refs/`-directory that was hand-edited or corrupted and now holds
garbage that does not parse as a 40-character hexadecimal SHA-1 — then the
clone prints the normal "Cloning into '...'" line, prints "done.", and then
aborts the whole process: it prints an internal BUG diagnostic into stderr,
something like

```
BUG: <source file>:NNNN: create called without valid new_oid
```

and then dies by abort signal, with a non-zero exit status. A user who saw
this would report "cloning this repo crashes git instead of telling me what
is wrong".

The affected behaviour is a local clone whose source repository contains
such a malformed ref file: instead of crashing with an internal BUG
diagnostic and an aborted process, the command must fail *gracefully* — it
must report an ordinary fatal error message (a normal `fatal: ...` line),
exit with the normal non-zero status used for a failed git command, print no
internal `BUG:` diagnostics at all, and leave no crash artifacts behind. The
same crash happens for any local clone of a repository that contains such a
malformed ref file, wherever that ref sits (heads, tags, remote-tracking
refs, any namespace).

Note: a completely empty ref list or a source repo with no refs at all is
not the issue here; the crash needs a ref file that exists but whose
contents are not a valid object id.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.sh` — your own minimal reproduction of the
   symptom described above. Its contract:

   - It must honour an environment variable `GIT_BIN` naming the git binary
     to execute, defaulting to `/app/src/git` when unset.
   - It must set up its scenario in a fresh scratch directory under `/tmp`:
     one non-bare local repository that contains at least one commit, with
     one of its loose ref files under `.git/refs/` overwritten so that its
     contents are **not** a valid object id (e.g. a short string that is
     not 40 hexadecimal characters).
   - It must then run the affected command exactly — a plain local
     `"$GIT_BIN" clone <source-repo> <destination>` from a scratch working
     directory, with no extra options.
   - It prints everything git prints (stdout and stderr), and nothing else.
   - It exits 0 if and only if the clone **failed cleanly**: the clone did
     not succeed (non-zero exit status), it did not die from an abort
     signal, its output contains no line beginning with `BUG:`, and git
     produced an ordinary `fatal:` error diagnostic on stderr. It exits
     non-zero in every other case — including when the clone succeeds, when
     the process is killed by an abort signal, and when the output shows
     the internal `BUG:` diagnostic.
   - It must work no matter what the current working directory is when it
     is invoked, and it must not touch anything outside its scratch
     directory except `/tmp` itself.

   On the **unfixed** tree this script must fail: the clone aborts with the
   BUG diagnostic, so the script exits non-zero. Confirm that now, before
   fixing anything, and keep that observation.

2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.sh` passes (exit 0: the clone now fails cleanly with an
   ordinary fatal error, no BUG output, no crash), also after a fresh
   `make -j1`. Fix the mechanism, not just one input: the same defect is
   reachable with the malformed ref in any namespace and with any
   non-object-id contents (see Grading). Do not merely special-case your
   reproduction in a wrapper script — the graded checks exercise the code
   path directly through the built binary.

3. **Break nothing else.** Everything else must keep working exactly as
   before: cloning local repositories with well-formed refs (which must
   still succeed), cloning by URL, remote fetches and pushes, and every
   other ref operation. The project's own test suite must stay green.

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
   `/tmp`, never inside `/app/src`): a small local repository with one
   commit, a corrupted loose ref file, then the local clone. Observe the
   BUG diagnostic and the aborted process. Try a couple of siblings — the
   same malformed ref placed under `refs/tags/`, a file holding only zeros,
   an empty ref file — to see that the crash follows the malformed ref, not
   the specific bytes you happened to write.
2. **Localise** the bug by reading the code. Trace what happens, on a local
   clone, when the source repository's refs are listed and the malformed
   ref yields no parseable object id, and where the code decides that such
   a "ref" is an internal error worth terminating the entire process for.
   Understand *why* an ordinary failure path already exists for this
   situation before you patch.
3. **Fix** with the smallest possible change in that one source file,
   rebuild (`make -j1`), and confirm `/app/repro.sh` passes.
4. **Prove nothing else broke**: run the project's own local-clone and ref
   test suites from `/app/src/t/`, for example `./t5605-clone-local.sh`,
   `./t5604-clone-reference.sh` and `./t1404-update-ref-errors.sh` (each
   prints `# passed all N test(s)` when green). A crashy binary aborting
   mid-suite will show up there as a failed test.
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
  exist in this tree) into `t/t5605-clone-local.sh`, run the whole `t5605`
  suite, and require the new test and all previous tests to pass;
- run a selection of the project's existing clone/ref suites
  (`t5601-clone.sh`, `t5600-clone-fail-cleanup.sh`,
  `t1404-update-ref-errors.sh`) and require them to pass;
- run authored hidden cases exercising the same code path from corrupt-ref
  inputs the upstream regression test does not use (a non-hex ref file in
  `refs/tags/`, a ref file holding an all-zero object id, an empty ref file
  in a nested namespace), each run against the rebuilt binary and each
  required to crash against the pre-fix binary.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.