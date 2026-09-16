# Build & reproduction recipe (authored for this task)

The tree is the REAL google/guava source at the pinned commit in `/app/src`
(working tree clean). There is **no network** in the trial container; every
dependency is baked in at `/opt/jars`. JDK 21 (`javac`, `java`) is on `PATH`.

## Compile the library once (plain javac, no Maven)

```bash
cd /app/src
mkdir -p /tmp/cls
time javac -J-Xmx3g -cp "/opt/jars/*" -d /tmp/cls $(find guava/src -name '*.java')
```

This produces ~1800 class files in `/tmp/cls` in about a minute at 1 vCPU.
After you change one source file, recompile just that file into the same
directory — javac resolves unchanged dependencies from the class files already
on the classpath:

```bash
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls <the-file-you-changed>
```

## Reproduce the symptom

`/app/Reproducer.java` (also printed in `instruction.md`) uses only public API:

```bash
cd /app
javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls Reproducer.java
timeout 30 java -cp "/tmp/cls:/opt/jars/*" Reproducer
echo "exit=$?"
```

On the buggy tree this prints
`BUG: IllegalArgumentException thrown: length (-1) may not be negative` and
exits 1. On a correct tree it prints `no exception; isEmpty=true` then `OK`
and exits 0. Wrap runs in `timeout` so a hang or crash cannot stall you.

## Run the project's own existing tests

The project's tests are JUnit 3 (`extends TestCase`) and live at
`guava-tests/test/...`. The test class covering the `ByteSource` API is
`guava-tests/test/com/google/common/io/ByteSourceTest.java`. Compile the test
support library and the io test support classes the test needs:

```bash
cd /app/src
mkdir -p /tmp/cls
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  $(find guava-testlib/src -name '*.java')
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  guava-tests/test/com/google/common/io/IoTestCase.java \
  guava-tests/test/com/google/common/io/TestOption.java \
  guava-tests/test/com/google/common/io/TestByteSource.java \
  guava-tests/test/com/google/common/io/TestByteSink.java \
  guava-tests/test/com/google/common/io/AndroidIncompatible.java \
  guava-tests/test/com/google/common/io/ByteSourceTester.java \
  guava-tests/test/com/google/common/io/SourceSinkTester.java \
  guava-tests/test/com/google/common/io/SourceSinkFactory.java \
  guava-tests/test/com/google/common/io/SourceSinkFactories.java \
  guava-tests/test/com/google/common/io/TestStreamSupplier.java \
  guava-tests/test/com/google/common/io/TestInputStream.java \
  guava-tests/test/com/google/common/io/TestOutputStream.java \
  guava-tests/test/com/google/common/io/CloserTest.java \
  guava-tests/test/com/google/common/io/RandomAmountInputStream.java \
  guava-tests/test/com/google/common/io/CharSourceTester.java \
  guava-tests/test/com/google/common/io/TestCharSink.java \
  guava-tests/test/com/google/common/io/TestCharSource.java \
  guava-tests/test/com/google/common/io/TestReader.java \
  guava-tests/test/com/google/common/io/TestWriter.java \
  guava-tests/test/com/google/common/io/CharSinkTester.java \
  guava-tests/test/com/google/common/io/ByteSourceTest.java
```

`ByteSourceTest` is a JUnit3 `TestCase` whose methods are run one at a time.
Instantiate it with the method name and run it through a `TestResult`:

```java
import junit.framework.TestResult;
import com.google.common.io.ByteSourceTest;
...
ByteSourceTest t = new ByteSourceTest("testSlice");
TestResult r = new TestResult();
t.run(r);
// r.wasSuccessful(); r.failureCount(); r.errorCount(); r.runCount()
```

The existing `ByteSourceTest` methods (testSlice, testSize, testRead_toArray,
testConcat, ...) must stay green after your fix. When the whole class runs
green the fix has broken nothing in this API; the same harness is what the
grader uses.

Do not modify the `.git` directory (its history is intentionally shallow), and
do not commit, fetch or pull.