# Fix a real bug in `git stash --include-untracked` with glob pathspecs

## Situation

`/app/src` is a shallow, pinned clone of the upstream `git/git` repository at
commit `7b556aa4b80ddfedb3de25e8787acd6c69d8799c`. It is **pristine upstream
bytes**; nothing in it has been altered or intentionally broken. The tree has
already been built once during image preparation, so a fresh `git` binary
exists at `/app/src/git`, and incremental rebuilds (one source file) take only
seconds even on this machine's single CPU.

The environment has no network at trial time: everything you need is in the
image. The machine is pinned to 1 CPU.

## The bug

Running `git stash` with the `--include-untracked` (`-u`) flag while passing a
**glob-magic pathspec** fails partway through the operation. For example, in a
repository containing a tracked file and an untracked `untracked.txt`:

```sh
/app/src/git -C <repo> stash -u -- ':(glob)**/*.txt'
```

produces output like

```
Saved working directory and index state WIP on master: ...
fatal: pathspec '**/*.txt' did not match any files
```

The command **exits non-zero**, and although a stash is created, the untracked
files are **left behind in the working tree** instead of being stashed and
removed. The stash should instead succeed: the files matched by the glob
pathspec must be moved into the stash and removed from the working tree,
recoverable later with `git stash pop`. Non-glob pathspecs with `-u` work
fine, as does `git stash -u` with no pathspec; the failure is specific to
passing a glob-magic pathspec together with `--include-untracked`.

A ready-made reproducer is at `/app/repro.sh` (it prints the command's exit
code and the resulting worktree contents). Reproduce it yourself, then find
the root cause in the source, fix it there, and prove the fix.

Your fix must be a real repair of the repository's own source and its own
`git` binary: do not stub out the feature, hardcode a wrapper, or edit the
harness. The verifier builds `git` from your repaired tree and runs it.

## What is on disk and what is installed

- `/app/src` - the git source tree you must repair, already built once.
  Everything under it is writable.
- `/app/src/git` - the binary built from this tree; this is what is tested.
- `/app/repro.sh` - an authored convenience reproducer (do not modify it).
- Compiler toolchain, zlib/OpenSSL/libcurl/Expat development libraries, Perl,
  and a system `git` (`/usr/bin/git`, a much newer version) are installed.
  The system `git` is **not** what is being tested; always run the tree's own
  binary (`/app/src/git`) and its own test suite.
- `/usr/bin/git` is a recent release that does not show this bug, so do not
  use it to judge whether the tree is fixed; use `/app/src/git`.

## How to iterate

```sh
cd /app/src
make              # incremental; recompiles only what changed, then relinks
```

The project's own test suites for `git stash` live in `t/` and are run from
there (they exercise the freshly built binary automatically):

```sh
cd /app/src/t
./t3903-stash.sh                         # the general stash suite
./t3905-stash-include-untracked.sh       # the -u suite (as checked out)
```

Your repair must keep these suites green. Note: the working tree's
`t/t3905-stash-include-untracked.sh` is the state at the parent commit, so
rely on `/app/repro.sh` (or your own repro) to confirm the glob case, since
that specific regression test is not yet present in the checked-out test file.

## Deliverables

1. **`/app/src`** - the repaired git source tree, rebuilt so that
   `/app/src/git` correctly handles `git stash -u` with glob-magic pathspecs
   (succeeds, removes the matched untracked files, restores them on
   `git stash pop`), and so that the existing stash test suites still pass.

2. **`/app/diagnosis.md`** - a plain-text file of at least a few sentences
   explaining the root cause: which C file contains the defect, exactly why
   the glob magic is lost by the time the pathspec reaches the internal
   commands that move and drop the files, and what you changed to fix it.
   (You must find and name the file yourself; the instruction intentionally
   does not.)

Verify your fix with `/app/src/git` before finishing: the repro must exit 0,
`untracked.txt` must be gone from the worktree, and `git stash pop` must
restore it.
