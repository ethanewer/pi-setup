# Repair a regression in the Trino SQL parser

## Environment

- `/app/src` is a shallow clone of the pinned upstream repository
  `trinodb/trino` (master, 484-SNAPSHOT, commit
  `0984974677197ff76bae9fc4f4950eb30a96306a`) — the real Trino project:
  about 7,000 files, 960,000 lines of Java, 109 Maven modules. The checkout
  is **not** pristine: a small bug was introduced somewhere in the SQL parser
  while the image was built. Everything else in the tree is true upstream.
- Toolchain baked in: Temurin **JDK 25** (`JAVA_HOME=/opt/java`) and **Maven
  3.9.16**, both on `PATH`. The Maven local repository (`/root/.m2`) is
  already warm with every dependency the parser module and its tests need.
- There is **no network** at trial time. Always pass `-o` (offline) to
  Maven. Only the `test` phase and the flags below are guaranteed to work —
  do not run `mvn clean`, `install`, `deploy` or any phase whose plugins were
  not exercised during image build; they will fail offline.
- The machine has **one CPU**. Maven runs sequentially by default; do not use
  `-T` or `-j`. A full module test run costs tens of seconds; budget your
  iterations.

## The task

The project's own test suite for the parser module is the definition of
correct behaviour, and it is the acceptance gate:

```
cd /app/src
mvn -B -o -f core/trino-parser/pom.xml \
    -Dmaven.source.skip=true -Dair.check.skip-all=true \
    -Dmaven.javadoc.skip=true test
```

Today that command does **not** exit 0: some tests fail. There is a single
root cause somewhere in the real source tree. Find it, fix it so the whole
module test suite passes, and write a short diagnosis to
`/app/fix-summary.md` (2–5 sentences: the symptom you observed, the file and
the specific code you changed, and why the change is correct).

You may run any subset while debugging, for example:

```
mvn -B -o -f core/trino-parser/pom.xml \
    -Dmaven.source.skip=true -Dair.check.skip-all=true \
    -Dmaven.javadoc.skip=true -Dtest=TestTypeParser test
```

The checkout's git tooling (`git log`, `git status`, `git diff`, `git show`)
is available if you want to inspect state — the regression is recorded in
the tree's history — but do **not** use `git checkout`, `git reset` or
`git stash` to revert files: the committed state carries the bug, so
restoring it would discard your fix and bring the regression back.

## Constraints

- Do not modify, create or delete anything under
  `core/trino-parser/src/test/`, and do not modify any `pom.xml` or any
  build configuration file. The verifier only accepts a change to the
  module's **main sources** (files under `core/trino-parser/src/main/`); a
  tree with no such change, or with changes to test or build files, scores 0.
- Leave your fix as an **uncommitted working-tree change** — do not `git
  commit` it. The verifier inspects the working tree with `git status`; a
  clean checkout (git status empty), which is what committing leaves behind,
  scores 0.
- The fix must be a real repair of the parser sources — not a wrapper, not a
  side-channel, not a weakened test run.

## Deliverables

1. `/app/src` — the fixed checkout: with your change applied, the acceptance
   command above exits 0.
2. `/app/fix-summary.md` — your diagnosis of the regression.