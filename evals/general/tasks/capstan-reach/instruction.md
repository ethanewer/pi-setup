# capstan-reach

You are working inside a real open-source codebase: **Guava** (`google/guava`),
Google's core Java libraries, checked out at a pinned commit in `/app/src` (the
working tree starts clean at that commit). There is a bug in this tree's
byte-source IO machinery. Your job is to find it, fix it in the working tree,
and prove the fix with the project's own test tooling and your own reasoning.
You are deliberately **not** told which file or function to change: localising
the bug is part of the task.

## Environment

- OpenJDK 21 (`javac`, `java`) and `git` are installed and on `PATH`. Maven is
  **not** used: the library compiles with plain `javac` against a small set of
  jars already baked in at `/opt/jars/*` (Guava annotation, checker, test and
  runtime dependencies, all present; no network needed).
- **There is no network** in this container. Everything is already on disk.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is a shallow (single-commit), detached clone. Do
  **not** `git commit`, `git fetch`, `git pull`, or otherwise modify `.git`.
- `/app/README-BUILD.md` has the exact copy-paste compile and test recipes.

## The bug (user-visible symptom)

`ByteSource.slice(offset, length)` returns a read-only view of at most
`length` bytes of a byte source, starting at `offset`. The class's own
documentation promises that a slice whose start lies *beyond* the source is
simply empty:

> "If `offset` is greater than the size of this source, the returned source
> will be empty."

But a defensive program that slices an already-sliced source — calling
`slice()` again on the result of a `slice()`, with the second offset past the
first slice's length — crashes with an `IllegalArgumentException`
("length (-1) may not be negative") instead of getting the documented empty
source. Any code that hands out bounded windows over byte sources and then
re-slices them past the window end can fail at runtime on inputs where the
contract promises an empty result.

Reproduce it (the author-flagged recipe is also at `/app/Reproducer.java`):

```bash
cd /app/src
mkdir -p /tmp/cls
time javac -J-Xmx3g -cp "/opt/jars/*" -d /tmp/cls $(find guava/src -name '*.java')
cd /app
javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls Reproducer.java
timeout 30 java -cp "/tmp/cls:/opt/jars/*" Reproducer
echo "exit=$?"
```

`Reproducer.java` evaluates `ByteSource.concat().slice(0, 3).slice(4, 3)` —
an empty source sliced to 3 bytes, then sliced again starting *past* that
window's end. On the buggy tree this throws: you see
`BUG: IllegalArgumentException thrown: length (-1) may not be negative` and
`exit=1`. The correct behaviour, per the documented contract, is to print
`no exception; isEmpty=true`, then `OK`, and exit 0.

## Requirements

1. Fix the tree so that the reproduction above prints
   `no exception; isEmpty=true` and `OK` and exits 0.
2. The exception is a symptom: the underlying defect is that slicing a sliced
   source with an offset past the slice's length must yield an **empty**
   source, not recurse into an illegal negative-length slice. Fix the
   mechanism, not just this one input — the same bug is reachable from many
   other sources, offsets and nesting depths (see Grading). Do not merely catch
   the exception around this one call, and do not patch anything outside the
   library source.
3. Everything else must keep working exactly as before: plain slices that stay
   inside the source, slicing at the very end of a source, `wrap`, `concat`,
   `empty`, `read`, `openStream`, hashing and file-like sources must all be
   unchanged. The project's existing `ByteSourceTest` methods (see
   `/app/README-BUILD.md` for how to run them) must stay green.
4. The graded tree must differ from the pinned commit in **exactly one source
   file** — the single file where the bug lives (the file you must discover).
   The duplicate copy of the same file under the project's `android/` mirror
   tree may also be changed, but is not required. Do not add, move, delete,
   rename or reformat any file; delete any scratch files you create outside
   `/tmp`; make no commits; do not modify `tests/`, `pom.xml`,
   `build.gradle` or any metadata file. The grader compares every tracked
   file's bytes against the pinned commit's own blobs, so cosmetic
   side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you changed,
   and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the recipe above (scratch files in `/tmp`, never inside
   `/app/src`), wrapping runs in `timeout`.
2. **Localise**: trace what `slice()` actually does when the source is *itself
   already a slice*. Read the slicing implementation — how a sliced source
   records its offset and remaining length, what recursing `slice()` computes
   when the new offset is past that remaining length, and which precondition of
   the public `slice()` (offset and length must not be negative) ends up being
   violated. Understand *why* a negative number is produced before you patch.
3. **Fix** with the smallest possible change in the one source file, recompile
   just that file (`javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls
   <that-file>`), and confirm the reproduction prints the expected output and
   exits 0.
4. **Prove nothing else broke**: run the project's own `ByteSourceTest`
   methods (e.g. `testSlice`, `testSize`, `testRead_toArray`, `testConcat`,
   `testCopyTo_byteSink`) via the JUnit3 harness recipe in
   `/app/README-BUILD.md`; every one passes on the pristine tree and must still
   pass after your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`, which you do not see) will, on your
final tree:

- assert that `HEAD` is still the pinned parent commit, and that every tracked
  file **except the single source file the bug lives in** is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails, including `assume-unchanged`/`skip-worktree` tricks);
- require `/app/summary.md` to exist and be non-empty;
- recompile the whole library from your tree (proving it compiles) and run the
  project's **own regression test** for this bug (baked into the image at
  `/opt/golden` — upstream added it with the fix, so it is not in this tree)
  via the project's JUnit3 harness: on the unfixed tree it errors with
  "length (-1) may not be negative", on your fixed tree it must pass;
- run the project's **own existing** `ByteSourceTest` methods, which must stay
  green;
- run the direct reproduction under a timeout: it must print
  `no exception; isEmpty=true` and exit 0;
- run **hidden cases** — other sources (non-empty wrapped byte arrays,
  three-level nesting, stream consumption) reaching the same broken code path
  from inputs the upstream test does not use, and must now produce an empty
  source with exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.