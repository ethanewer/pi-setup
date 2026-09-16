# CSV argument trimming must be ASCII-only

## Situation

`/app/src` is a fresh, pinned, shallow clone of the JUnit 5 framework repository
(`junit-team/junit5`), checked out at one specific upstream commit from late
2025. The tree is exactly the upstream code at that commit — bug included. It is
not a workspace you may re-initialise: no new commits, no history rewrite, no
remotes, no fetches (fetches would fail anyway: there is no network).

The toolchain is already installed and configured:

- JDK 24.0.2 (Temurin) at `/opt/jdk-24.0.2+12` — the build's default Java
  toolchain and the Gradle daemon JVM (the repository's
  `gradle/gradle-daemon-jvm.properties` pins `toolchainVersion=24`). `JAVA_HOME`
  points there and `JDK24` is exported for Gradle's toolchain auto-detection
  (`org.gradle.java.installations.fromEnv`).
- JDK 21 (apt, `/usr/lib/jvm/java-21-openjdk-amd64`, exported as `JDK21`) and
  JDK 25.0.4.1 (Temurin, `/opt/jdk-25.0.4.1+1`, exported as `JDK25`) for the few
  build tasks in the dependency closure that need them.
- Gradle 8.14.2 through the project's own checked-in wrapper (`./gradlew`; the
  wrapper distribution is SHA256-pinned by the wrapper itself). All
  third-party dependencies are already downloaded, and the tree has already
  been compiled and its CSV-provider test classes executed once, so Gradle
  invocations are fast and incremental.
- **There is no network at trial time.** `git fetch`, plugin resolution and
  dependency downloads will not work. Run Gradle with `--offline` and it will
  not even try. Everything you need is in the image.

## The bug

`@CsvSource` and `@CsvFileSource` turn CSV records into argument sets for
parameterized tests. By default (`ignoreLeadingAndTrailingWhitespaces = true`,
the documented behaviour since JUnit 5.8), the leading and trailing whitespace
of each **unquoted** column is trimmed before the value reaches the test. Quoted
columns are never trimmed.

That trimming was recently switched to a newer, Unicode-aware String API. The
two whitespace notions disagree about real characters:

- **Non-ASCII Unicode whitespace** (code points above U+0020 that Java's
  whitespace detection accepts) — e.g. the thin space U+2009, the
  ideographic space U+3000 or the line separator U+2028 — is now silently
  **removed** from argument values. Before the change it was preserved (it is
  not part of the ASCII whitespace range).
- **Control characters below U+0020 that are not Unicode whitespace** — e.g.
  NUL U+0000, U+0001 start of heading, U+000E shift out — are now **no longer
  trimmed at all**. Before the change they were removed like any other character
  up to U+0020.

So the values a parameterized test actually receives changed between releases
without any change to the test source: data that used to contain a leading
non-breaking space now arrives without it, and data that used to be trimmed of
trailing control characters now keeps them. Suites that compare against
file-based CSVs or embed such characters silently alter or break. The values a
test receives must go back to the original contract: trimming applies **only to
ASCII whitespace**, i.e. to characters with code points less than or equal to
U+0020, exactly the semantics of the classic `String.trim()`.

## Reproducing

Drive your work with the project's own test runner, exactly like this (the same
command is available as `/app/run_tests.sh`; it must be green once you are
done):

```
cd /app/src && ./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" \
  -Ptesting.enableJaCoCo=false --offline
```

The tree already carries the project's own regression test for this bug: the
file `jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java`
is present as a working-tree modification (see `git status`) and contains the
test `trimsSpacesUsingStringTrim`, which drives the reader through the public
provider API with rows mixing U+0000 and U+00A0 on both sides of the trim. In
this checkout the whole class runs except that one test: it fails with output
like

```
Expecting actual: [["\u0000foo", "\u00A0bar"], ...] to contain exactly
(and in same order): [["foo", "\u00A0bar"], ...]
```

Take that regression test as the specification of correct behaviour. Note that
it only samples one non-ASCII whitespace character and one control character;
the verifier checks the same contract more broadly than the regression test
does.

The sibling class `CsvFileArgumentsProviderTests` exercises the same reader
through the file-source path and is fully green at this commit:

```
cd /app/src && ./gradlew :jupiter-tests:test \
  --tests "org.junit.jupiter.params.provider.CsvFileArgumentsProviderTests" \
  -Ptesting.enableJaCoCo=false --offline
```

It must stay green once you are done.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. `CsvArgumentsProviderTests` (including `trimsSpacesUsingStringTrim`) passes
   end to end;
2. `CsvFileArgumentsProviderTests` stays green;
3. the working tree remains at the pinned commit with only the minimal
   production-code change the fix needs: no other tracked file modified, no new
   files added, no history rewritten, no remotes, no commit.

Do not "fix" the regression test itself or any other test: the verifier holds
`CsvArgumentsProviderTests.java` byte-identical to the upstream regression test,
so editing it fails the task. A correct fix changes project source only. Use
the regression test's expectations as your diagnostic guide — the bug lives in
the CSV reader shared by both sources, in the line that performs the trimming
of unquoted columns. Hint: the tree is full of contextual clues; the trimming
line itself is one character of API surface away from the original behaviour.

If you write scratch tests to explore (a reasonable approach), keep them out of
the repository when you finish — the final tree must contain only the fix.

## Constraints

- Network is unavailable; everything needed is already installed and cached.
- The clone at `/app/src` is the deliverable.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.
- The verifier additionally checks that the upstream fix commit is not
  reachable from the clone and that the working tree stays at the pinned
  parent commit with the minimal diff described above.

## What the verifier checks

1. The tree is still at the pinned commit; the fix commit is not reachable from
   the object store; only the production source file(s) behind the shared CSV
   reader may differ from the delivered baseline (plus the overlaid
   regression-test file, which must stay byte-identical to the upstream
   regression test); the buggy production line was actually changed; no
   untracked or other modified files remain.
2. The project's own `CsvArgumentsProviderTests` class — including the
   regression test `trimsSpacesUsingStringTrim` — passes.
3. The project's own `CsvFileArgumentsProviderTests` class passes.
4. Hidden cases exercise the same code path from inputs the upstream regression
   test does not use: a family of other Unicode whitespace characters above
   U+0020 (U+00A0, U+1680, U+2009, U+202F, U+205F, U+3000, U+2028/U+2029) and
   non-whitespace controls (U+0001, U+0002, U+000E, U+001B) through the
   text-source reader, plus the same contract through the file-source reader,
   with trimming disabled and with quoted columns as guards.

Deliverable: the repaired `/app/src` tree.