# capstan-hull

You are working inside a real open-source codebase: **Apache Commons Lang**
(`apache/commons-lang`), the Java utility library, checked out at a pinned
commit in `/app/src` (the working tree starts clean, detached at that commit).
There is a real bug in this tree's rational-number arithmetic. Your job is to
find it, fix it in the working tree, and prove the fix with the project's own
Maven test tooling. You are deliberately **not** told which file or method to
change: localising the bug is part of the task.

## Environment

- OpenJDK 21 and Maven 3.9.9 are installed; Maven is at
  `/opt/apache-maven-3.9.9/bin/mvn` (add it to `PATH` or call it by that
  path). `git` and `javac` are available.
- **There is no network** in this container. Everything needed is baked in:
  the project was compiled at build time and the offline Maven local
  repository lives at `/opt/m2repo`. Always pass
  `-Dmaven.repo.local=/opt/m2repo` to every `mvn` invocation (and
  `-Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true
  -Denforcer.skip=true -DfailIfNoTests=false`), exactly like this:
  ```bash
  cd /app/src
  /opt/apache-maven-3.9.9/bin/mvn -B -q test \
    -Dtest='SomeTest#someMethod' -DfailIfNoTests=false \
    -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
    -Dmaven.repo.local=/opt/m2repo
  ```
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- The tree at `/app/src` is shallow (a single commit object) and detached; do
  not commit, fetch, or otherwise touch `.git`.

## The bug (user-visible symptom)

The library's fraction type lets you build fractions that are mathematically
correct but not reduced to lowest terms. Multiplying two fractions can then
throw `java.lang.ArithmeticException: overflow: mulPos` — even when the
correctly reduced product fits comfortably in a 32-bit `int` — whenever either
operand carries an internal factor that should have been cancelled first. The
internals cancel common factors only across the two operands and silently
assume each operand is already reduced, so a factor shared inside a single
operand survives into an intermediate product that the reduced result would
never need. The same failure also strikes `divideBy` (which delegates to the
same code) and the power operation.

A concrete valid computation that fails today:

- `-1/46341 × 100/1000000` — the reduced product is `-1/463410000`, every
  numerator and denominator fits an `int`, yet the call throws.

Reproduce it with the probe that ships in the image:

```bash
/app/probe.sh
```

On the buggy tree this prints `THREW java.lang.ArithmeticException:
overflow: mulPos` and exits 1 (or later FAIL lines on some checks). On a fixed
tree it prints `RESULT=true (all fraction multiplication checks passed)` and
exits 0.

## Requirements

1. Fix the tree so that `/app/probe.sh` exits 0 with
   `RESULT=true (all fraction multiplication checks passed)`. The same input,
   run before your fix, throws the overflow exception and exits 1.
2. Fix the mechanism, not just this one input: any unreduced operand must be
   handled (the same defect is reachable through `divideBy`, through powers,
   and from many other input values; the grader plants tests with different
   numbers — see Grading). Do **not** catch-and-suppress the exception: a
   product whose reduced numerator or denominator genuinely exceeds
   `Integer.MAX_VALUE` must still throw an `ArithmeticException` exactly as
   today.
3. Everything else must keep working exactly as before: multiplication,
   division, reduction, comparison, conversion and formatting of ordinary
   (already-reduced or ratio-constructed) fractions must be unchanged. The
   project's own test suite around the class must stay green.
4. The graded tree must be byte-identical to the pinned commit except for the
   **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate,
   delete them before you finish; make no commits; do not modify `tests/`,
   `pom.xml` or any metadata file. The grader compares every file's bytes
   against the pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/probe.sh` (scratch files go in `/tmp`, never
   inside `/app/src`).
2. **Localise** the bug: the exception message is a string that lives next to
   the helper that throws it. Search the main sources for it, then read the
   multiplication routine that calls that helper: how does it cancel common
   factors, and what does it implicitly assume about its operands? Understand
   *why* the internal factor of an unreduced operand can overflow an `int`
   even when the reduced result fits, before you patch.
3. **Fix** with the smallest possible change in that one file. The contract
   of the method's result must not change — only the spurious failure goes
   away. Re-run `/app/probe.sh` to confirm `RESULT=true` and exit 0.
4. **Prove nothing else broke**: run the class's own test methods plus the
   project's math tests, e.g.

   ```bash
   cd /app/src
   /opt/apache-maven-3.9.9/bin/mvn -B -q test \
     -Dtest='FractionTest#testMultiply+testDivide,NumberUtilsTest' \
     -DfailIfNoTests=false \
     -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
     -Dmaven.repo.local=/opt/m2repo
   ```
   Every one of these passes on the pristine tree and must still pass after
   your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream fix
  commit is not reachable from the working clone (only the parent object
  exists there), and that every tracked file except the single source file
  the bug lives in is byte-identical to that commit (any other modification,
  added file or untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- run `/app/probe.sh` (must print `RESULT=true` and exit 0);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden/FractionTest.java` — upstream added it with the fix,
  so it does not exist in this tree), rebuild offline, and run its
  `testMultiply` and `testDivide` methods: they must pass, and the class's
  whole existing suite plus the other math test classes must still pass;
- run **hidden cases** — authored JUnit tests that exercise the same broken
  code path from inputs the upstream regression test does not use: products
  where *both* operands are unreduced and near the `int` limit, quotients
  with unreduced divisors, a power of an unreduced fraction, and guards that
  a genuinely overflowing product still throws.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.