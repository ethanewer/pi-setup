# ballast-hull

You are working inside a real open-source codebase: **Guava** (`google/guava`),
Google's core Java libraries, checked out at a pinned commit in `/app/src` (the
working tree starts clean at that commit). There is a bug in this tree's
immutable-collection machinery. Your job is to find it, fix it in the working
tree, and prove the fix with the project's own test tooling and your own
reasoning. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

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

An `ImmutableSet.Builder` created with an **expected size**
(`ImmutableSet.builderWithExpectedSize(n)`) does not behave correctly when it is
**reused to build more than one set**. The first `build()` call works; but when
you then keep adding elements to the *same* builder and call `build()` again to
produce a new set, memberships queries on the freshly built set can go wrong:
a simple `contains(...)` call **never returns** (the program hangs), or — in
other configurations — elements are silently lost or misreported. This affects
only sets produced by a *reused* sized builder; a builder used for a single
build is fine.

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

`Reproducer.java` builds `{0}` from a builder with expected size 6, then reuses
**the same builder** to build `{0,1,2,3}` and asks `contains(4)`. On the buggy
tree this **hangs**: `timeout` kills it and you see `exit=124` with no output —
the `contains(4)` call spins forever. The correct behaviour is to print
`contains(4)=false subject=[0, 1, 2, 3]` and `OK`, then exit 0.

## Requirements

1. Fix the tree so that the reproduction above prints
   `contains(4)=false subject=[0, 1, 2, 3]` and `OK` and exits 0.
2. The hang is a symptom: the underlying defect is in how the builder's internal
   state is maintained when a partially-built builder is reused. Fix the
   mechanism, not just this one input — the same bug is reachable from other
   expected sizes, element counts and element types, and also when the builder
   is reused to build three or more sets. Do not merely special-case `contains`
   or patch the test.
3. Build sets correctly as before: a builder used for a single `build()` must
   keep producing the same results; `contains`, `size`, iteration order and
   duplicate elimination must all stay correct. The project's existing
   `ImmutableSetTest` methods (see `/app/README-BUILD.md` for how to run them)
   must stay green.
4. The graded tree must differ from the pinned commit in **exactly one source
   file** — the single file where the bug lives (the file you must discover) —
   and in nothing else. Do not add, move, delete, rename or reformat any file;
   delete any scratch files you create outside `/tmp`; make no commits; do not
   modify `tests/`, `pom.xml`, `build.gradle` or any metadata file. The grader
   compares every tracked file's bytes against the pinned commit's own blobs,
   so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you changed,
   and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the recipe above (scratch files in `/tmp`, never inside
   `/app/src`), using `timeout` so a hang cannot stall you.
2. **Localise**: think about what a "builder with an expected size" must do when
   it is reused. Read the builder implementation — how the expected size shapes
   the internal hash table, what happens when `build()` is called (note that
   `build()` may resize the table to fit), and what bookkeeping values are (and
   are not) recomputed when that resize happens. The infinite loop in
   `contains` comes from a hash table that ends up completely full while the
   probe bound still assumes a much larger table. Understand *why* before you
   patch.
3. **Fix** with the smallest possible change in the one source file, recompile
   just that file (`javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls
   <that-file>`), and confirm the reproduction prints the expected output and
   exits 0.
4. **Prove nothing else broke**: run the project's own `ImmutableSetTest`
   methods (e.g. `testResizeTable`, `testEquals`, `testCreation_manyDuplicates`,
   `testChooseTableSize`, `testToImmutableSet`) via the JUnit3 harness recipe in
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
  under a timeout via the project's JUnit3 harness: on the unfixed tree it
  hangs, on your fixed tree it must pass;
- run 12 of the project's **own existing** `ImmutableSetTest` methods, which
  must stay green;
- run the direct reproduction under a timeout: it must print
  `contains(4)=false subject=[0, 1, 2, 3]` and exit 0;
- run **hidden cases** — other expected sizes, element counts, element types and
  a three-build reuse that reach the same broken code path and must now produce
  the correct membership results with exit 0.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.
