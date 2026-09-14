# Build & test recipe (authored for this task)

The tree is the REAL google/guava source at the pinned commit in `/app/src`
(working tree clean). There is **no network** in the trial container; every
dependency is baked in at `/opt/jars`. JDK 21 (`javac`, `java`) is on `PATH`.

## Compile the library once (plain javac, no Maven)

```bash
cd /app/src
mkdir -p /tmp/cls
time javac -J-Xmx3g -cp "/opt/jars/*" -d /tmp/cls $(find guava/src -name '*.java')
```

This produces thousands of class files in `/tmp/cls` in about a minute at
1 vCPU. After you change one or more source files, recompile just the files you
changed into the same directory — javac resolves unchanged dependencies from
the class files already on the classpath:

```bash
changed=$(git diff --name-only -- '*.java')
[ -n "$changed" ] && javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls $changed
```

The whole library compiles from scratch in well under a minute at 1 vCPU, so
re-running the full `find guava/src` command above is fine too.

## Run a scratch program against the library

```bash
mkdir -p /tmp/scratch
javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/scratch /tmp/scratch/MyProbe.java
java  -cp "/tmp/scratch:/tmp/cls:/opt/jars/*" MyProbe
```

`Lists.newArrayList(...)` from `com.google.common.collect` prints an iterable
of strings in the easily readable form `[a, b, c]`, which is handy for
inspecting split results.

## The reproduction deliverable

`/app/repro/SplitRepro.java` must be a single file with a `main` method that:

- uses only public Guava API (e.g. `Splitter.on(...)`, `Splitter.onPattern(...)`,
  `Lists.newArrayList(...)`);
- prints the results it computed (at least one line per case), and
- calls `System.exit(0)` only when every case behaved correctly, and
  `System.exit(1)` (with a stderr message saying which case failed and what it
  printed) otherwise.

The verifier compiles this file with plain `javac` twice: once against the
un-fixed pre-fix library and once against your fixed tree, and runs it both
times. So the file must compile against the *parent* library unchanged, too —
do not call into classes or methods that only exist after your edit.

An easy shape:

```java
import com.google.common.base.Splitter;
import com.google.common.collect.Lists;
import java.util.regex.Pattern;

public class SplitRepro {
  static int failures = 0;

  static void check(String label, Iterable<String> got, java.util.List<String> want) {
    java.util.List<String> g = Lists.newArrayList(got);
    System.out.println(label + " = " + g);
    if (!g.equals(want)) {
      System.err.println("FAIL " + label + ": got " + g + " want " + want);
      failures++;
    }
  }

  static void checkPattern(String label, String input, String regex, java.util.List<String> want) {
    check(label, Splitter.onPattern(regex).split(input), want);
  }

  public static void main(String[] args) {
    // cases covering the affected behaviour (you choose the inputs/patterns)
    // checkPattern("case1", "...", "...", java.util.Arrays.asList(...));
    // checkPattern("case2", "...", "(?=...)", java.util.Arrays.asList(...));
    if (failures > 0) {
      System.err.println(failures + " case(s) failed");
      System.exit(1);
    }
    System.out.println("OK");
  }
}
```

## Run the project's own tests

The project's tests are JUnit 3 (`extends TestCase`) under
`guava-tests/test/...`, plus its test-support library under
`guava-testlib/src`. For the string-splitting module the project's own test
class is `guava-tests/test/com/google/common/base/SplitterTest.java` (there is
also a same-directory `AndroidIncompatible.java` annotation file it imports):

```bash
cd /app/src
mkdir -p /tmp/cls
# once: the project's test-support library
javac -J-Xmx3g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  $(find guava-testlib/src -name '*.java')
# once: the test class itself
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  guava-tests/test/com/google/common/base/SplitterTest.java \
  guava-tests/test/com/google/common/base/AndroidIncompatible.java
```

Then run individual `test*` methods through a tiny JUnit 3 harness — the
standard trick is to build a `TestSuite` from the class, pick the method by
name, run it into a `TestResult`, and inspect its counters:

```java
import junit.framework.Test;
import junit.framework.TestResult;
import junit.framework.TestSuite;
import com.google.common.base.SplitterTest;

public class RunOne {
  public static void main(String[] args) throws Exception {
    String methodName = args[0];
    TestSuite suite = new TestSuite(SplitterTest.class);
    int ran = 0, failed = 0;
    for (int i = 0; i < suite.testCount(); i++) {
      if (suite.testAt(i).toString().startsWith(methodName + "(")) {
        TestResult r = new TestResult();
        suite.testAt(i).run(r);
        System.out.println(methodName + " ran=" + r.runCount()
            + " failures=" + r.failureCount() + " errors=" + r.errorCount());
        if (r.runCount() > 0 && r.failureCount() == 0 && r.errorCount() == 0) ran++; else failed++;
      }
    }
    System.out.println("ran=" + ran + " failed=" + failed);
    System.exit(ran >= 1 && failed == 0 ? 0 : 1);
  }
}
```

```bash
javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/scratch /tmp/scratch/RunOne.java
java -cp "/tmp/scratch:/tmp/cls:/opt/jars/*" RunOne testPatternSplitLookBehind
```

The existing `SplitterTest` methods (`testPatternSimpleSplit`,
`testPatternSplitLookBehind`, `testPatternSplitWordBoundary`,
`testFixedLengthSplitIntoChars`, ...) must stay green after your fix.