# Fix a real bug in `git notes add` with empty note contents

## Situation

`/app/src` is a shallow, pinned clone of the upstream `git/git` repository at
commit `39bf06adf96da25b87c9aa7d35a32ef3683eb4a4`. It is **pristine upstream
bytes**; nothing in it has been altered or intentionally broken. The tree has
already been built once during image preparation, so a fresh `git` binary
exists at `/app/src/git`, and incremental rebuilds (one source file) take only
seconds even on this machine's single CPU.

The environment has no network at trial time: everything you need is in the
image. The machine is pinned to 1 CPU.

## The bug

Creating a note whose body is **explicitly empty** unexpectedly launches the
configured editor, even though the note contents were fully supplied on the
command line. Any of these commands is affected in a freshly initialised
repository with at least one commit:

```sh
empty=$(git hash-object -w /dev/null)          # the SHA of the empty blob
/app/src/git notes add -C "$empty" --allow-empty
/app/src/git notes add -m "" --allow-empty
/app/src/git notes add -F /dev/null --allow-empty
```

Each command opens the editor. In a non-interactive environment the editor
cannot be used, so the command fails. For example, with an editor that always
fails:

```
$ GIT_EDITOR=false /app/src/git notes add -C "$empty" --allow-empty
error: there was a problem with the editor 'false'
fatal: please supply the note contents using either -m or -F option
```

The command **exits 128** and **no note is stored**. In an interactive
environment the same mistake is less dramatic but just as wrong: the user who
typed `-m ""` is suddenly dropped into an editor prompt that will decide the
note content.

The expected behaviour: when the note contents were supplied on the command
line via `-m`, `-F`, `-c` or `-C`, the editor must **never** be launched — with
or without `--allow-empty` — and when `--allow-empty` is given the empty note
must actually be **stored** (visible in `git notes list` and empty when shown
with `git notes show`). Two behaviours that must be preserved:

- `git notes add` with **no** content option at all still opens the editor
  (that is its normal, intended behaviour), and
- `git notes add -m "some real text"` must continue to store the note without
  opening the editor.

A ready-made reproducer is at `/app/repro.sh` (it prints the command's exit
code and the resulting notes state). Reproduce it yourself, then find the root
cause in the source, fix it there, and prove the fix.

Your fix must be a real repair of the repository's own source and its own
`git` binary: do not stub out the feature, hardcode a wrapper, or edit the
harness. The verifier rebuilds `git` from your repaired tree and runs it.

## What is on disk and what is installed

- `/app/src` - the git source tree you must repair, already built once.
  Everything under it is writable.
- `/app/src/git` - the binary built from this tree; this is what is tested.
- `/app/repro.sh` - an authored convenience reproducer (do not modify it).
- Compiler toolchain, zlib/OpenSSL/libcurl/Expat development libraries, Perl,
  and a system `git` (`/usr/bin/git`, an unrelated version from the same era)
  are installed. The system `git` is **not** what is being tested; always run
  the tree's own binary (`/app/src/git`) and its own test suite.
- Note that the system `git` may show the *same* failure (this defect shipped
  in several releases), so it is useless for judging whether the tree is
  fixed; use `/app/src/git`.

## How to iterate

```sh
cd /app/src
make              # incremental; recompiles only what changed, then relinks
```

The project's own test suite for the notes machinery lives in `t/` and is run
from there (it exercises the freshly built binary automatically):

```sh
cd /app/src/t
./t3301-notes.sh                        # the notes suite
```

Be aware that the working tree's `t/t3301-notes.sh` is the state at the
checked-out commit, so it **predates** the regression coverage for this exact
case and passes both before and after the fix; to confirm the editor
behaviour, rely on `/app/repro.sh` or your own direct reproduction.

## Deliverables

1. **`/app/src`** - the repaired git source tree, rebuilt so that
   `/app/src/git` never launches the editor when note contents were supplied
   via `-m`/`-F`/`-c`/`-C` (with or without `--allow-empty`), stores the
   empty note when `--allow-empty` is given, and still passes the notes test
   suite.

2. **`/app/diagnosis.md`** - a plain-text file of at least a few sentences
   explaining the root cause: which C file contains the defect, exactly why
   the editor is launched even though the note contents were supplied on the
   command line, and what you changed to fix it. (You must find and name the
   file yourself; the instruction intentionally does not.)

Verify your fix with `/app/src/git` before finishing: `bash /app/repro.sh` must
end with exit code 0, must not print `error: there was a problem with the
editor ...`, and `git notes list` must show the note stored with the empty
blob object id.