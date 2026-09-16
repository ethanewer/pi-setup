# Tests silently vanish from your run when a subclass in another package
# declares a method with the same signature

## Situation

`/app/src` is a fresh, pinned, shallow clone of the JUnit 5 framework
repository (`junit-team/junit5`), checked out at one specific upstream commit
from September 2025. The tree is exactly the upstream code at that commit —
bug included. It is not a workspace you may re-initialise: no new commits,
no history rewrites, no remotes, no fetches (fetches would fail anyway: there
is no network at trial time).

The toolchain is already installed and configured:

- JDK 25.0.4.1 (Temurin) at `/opt/jdk-25.0.4.1+1` — the build's default Java
  toolchain and the Gradle daemon JVM (the repository's
  `gradle/gradle-daemon-jvm.properties` pins `toolchainVersion=25`). `JAVA_HOME`
  points there and `JDK25` is exported for Gradle's toolchain auto-detection
  (`org.gradle.java.installations.fromEnv` in `gradle.properties`).
- JDK 24.0.2 (Temurin) at `/opt/jdk-24.0.2+12` and JDK 21 (apt,
  `/usr/lib/jvm/java-21-openjdk-amd64`), exported as `JDK24` and `JDK21`, for
  the few build tasks in the dependency closure that need them.
- Gradle 9.2.0 through the project's own checked-in wrapper (`./gradlew`; the
  wrapper distribution is SHA256-pinned by the wrapper itself). All
  third-party dependencies are already downloaded, and the `:jupiter-tests`
  dependency graph has already been built and its engine test slice executed
  once at image build time, so Gradle invocations are fast and incremental.
- **There is no network at trial time.** `git fetch`, plugin resolution and
  dependency downloads will not work. Run Gradle with `--offline` and it will
  not even try. Everything you need is already in the image.

## The bug

Consider an ordinary test class hierarchy within one project:

- a *superclass* test case declares a test method with **package-private**
  visibility (no modifier) — the class lives in some package, say package **A**;
- a *subclass* of that superclass, declared in a **different** package
  **B**, declares a method with the **same name and the same parameter list**.

Java's visibility rules are explicit here: a package-private method is only
overridden by a same-signature method declared *in the same package*. The two
methods above live in different packages, so the subclass method does **not**
override the inherited one. Java (correctly) lets both exist in the hierarchy,
and both are test methods — so a run of the framework must discover **both**
and execute **both**.

That is not what happens at this commit. Only **one** of the two methods is
discovered, and only that one executes. To a user this looks like this: they
had a test method in a superclass in one package that ran fine; they added a
new test method to a subclass in another package, giving it the same name and
parameter list; and the pre-existing test **silently disappears from the run**
— no error, no warning, no skipped marker, the summary just shows one test
where there used to be two. If three levels of the hierarchy each declare the
same-signature package-private test method in three different packages, two of
them silently vanish.

To repeat: this silent loss only happens for the *non-override* case above
(visible-package private method inherited across packages). A **genuine**
override — e.g. a *public* or *protected* superclass method overridden by a
same-signature subclass method — already behaves correctly at this commit and
must keep behaving correctly: exactly one test (the overriding one). Do not
"fix" the bug by treating every same-signature pair as distinct.

## The deliverable: write your own reproduction before you fix anything

The deliverable is `/app/reproduce.sh`: a self-contained script **you write**
that first demonstrates the bug through the framework's own machinery, proves
your fix removes it, and is itself re-run by the verifier. Contract:

```
usage: /app/reproduce.sh [CHECKOUT]
```

- `CHECKOUT` is a path to a checkout of the framework; it defaults to
  `/app/src`. The script must honour an explicitly given argument (the
  verifier invokes it against a second, pristine copy of the tree at the same
  pinned commit).
- On every invocation the script stages its **own** demonstration test
  classes under `$CHECKOUT/jupiter-tests/src/test/java/...` — the superclass
  with the package-private test method in one package, the subclass in a
  different package declaring the same-name same-parameter-list test method,
  plus a small driver test — removing any leftovers from earlier runs before
  staging fresh files.
- It then runs the **project's own test runner** on exactly the classes it
  staged, offline:
  `cd "$CHECKOUT" && ./gradlew :jupiter-tests:test --tests "<its staged driver class>" -Ptesting.enableJaCoCo=false --offline`
- It **exits 0 exactly when the demonstrated correct behaviour holds** (both
  methods discovered and both executed — 2 of 2) and **non-zero in every
  other case**: only 1 of 2 discovered or executed, a compilation failure, or
  any other failure.
- Before exiting it **removes every file it staged** and leaves the checkout
  exactly as it found it (this is verified afterwards).
- It must be self-contained: it may only use the checkout and the installed
  toolchain. It must not read anything under `/opt/golden`, `/tests` or
  `/solution`, must not touch `.git`, and must not need network.

Approach in the order that earns the marks: write the reproduction **first**
and run it here — it must genuinely **fail** on this unmodified tree (that
failure *is* the bug, demonstrated); then fix the framework so that both
methods are discovered and executed; then re-run your reproduction — it must
exit 0. A reproduction that cannot fail on the unmodified tree proves nothing;
one that is hard-wired to a fixed exit code fails the verifier's checks
below, because the verifier runs it both against an unmodified copy of the
tree (where it must fail) and against your repaired tree (where it must
pass).

## What the fix must satisfy

1. For the scenario above — a package-private test method inherited from a
   superclass in a different package and a same-signature test method
   declared in the subclass — **both** methods are discovered and **both** are
   executed, in one run of the framework's own engine.
2. The first rule extends naturally: a same-signature package-private test
   method declared at *every* level of a multi-level hierarchy (each level in
   a different package) is discovered and executed at every level.
3. Genuine overrides still collapse to one: a public or protected superclass
   test method overridden by a same-signature subclass method is executed
   exactly once.
4. The tree's own existing tests keep passing: `/app/run_tests.sh` (the
   engine test slice below) must stay green with your change.
5. No test files are modified and no test files are added, permanently. Your
   reproduction stages and removes its own files; the final tree must contain
   only your changes to **production** source. In particular, do not delete,
   rename, skip or alter any existing test, and do not hide the bug by
   editing Gradle configuration.

You are expected to change only the minimal production code the diagnosis
requires: the framework's discovery/selector machinery under the
`junit-jupiter-engine/src/main`, `junit-platform-engine/src/main` and
`junit-platform-commons/src/main` trees. Do not edit anything under
`jupiter-tests/`, `documentation/`, `gradle/`, or build files.

## Constraints

- The clone at `/app/src` is the deliverable, together with
  `/app/reproduce.sh`. The tree must remain at the pinned commit: `HEAD`
  unchanged, no commits, no `.git` mutations of any kind, no remotes, no
  fetches.
- Keep the working tree minimal: modified files may only be production
  sources under the three `.../src/main` trees listed above, and at least one
  of the bug's own files must actually change (a no-op is not a fix).
- `/opt/golden`, `/tests` and `/solution` are harness-owned — do not read or
  modify them.
- No network. Do not remove or reconfigure anything that the build needs.

## What the verifier checks

1. **Tree provenance**: still at the pinned upstream commit, the upstream fix
   commit not present in the object store, no commits and no `.git`
   mutations; every modified tracked file is a production source under the
   three `.../src/main` trees; no new files; at least one of the bug's files
   actually changed.
2. **Your reproduction, both ways**: run against a pristine pre-fix copy of
   the tree at the same pinned commit (must exit **non-zero** — it must
   genuinely detect the bug), and against `/app/src` with your fix (must exit
   **zero**).
3. **The framework's own regression tests for this bug** — extracted from the
   upstream fix revision at image build time into the harness-owned
   `/opt/golden` — pass against your tree, together with hidden cases that
   exercise the same discovery path from inputs the upstream tests do not use
   (other signatures, a second hierarchy depth, and the genuine-override
   guard).
4. **The tree's own slice** (`/app/run_tests.sh`): the engine test classes
   listed there must all pass on your repaired tree.

The deliverable is the repaired `/app/src` plus `/app/reproduce.sh`.