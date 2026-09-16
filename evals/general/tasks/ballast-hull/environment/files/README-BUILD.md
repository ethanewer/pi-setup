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
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  guava/src/com/google/common/collect/ImmutableSet.java
```

## Reproduce the symptom

`/app/Reproducer.java` (also printed in `instruction.md`) uses only public API:

```bash
cd /app
javac -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls Reproducer.java
timeout 30 java -cp "/tmp/cls:/opt/jars/*" Reproducer
```

On the buggy tree this call **never returns** (`timeout` kills it, exit code
124, no output printed). On a correct tree it prints
`contains(4)=false subject=[0, 1, 2, 3]` then `OK` and exits 0.

## Run the project's own existing tests

The project's tests are JUnit 3 (`extends TestCase`) and live at
`guava-tests/test/...`. For `ImmutableSet`, compile the project's test support
and run individual methods through a small harness:

```bash
cd /app/src
mkdir -p /tmp/cls
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  $(find guava-testlib/src -name '*.java')
javac -J-Xmx2g -cp "/tmp/cls:/opt/jars/*" -d /tmp/cls \
  guava-tests/test/com/google/common/collect/ImmutableSetTest.java \
  guava-tests/test/com/google/common/collect/AbstractImmutableSetTest.java
```

Writing a small `main` that instantiates `ImmutableSetTest` via
`new TestSuite(ImmutableSetTest.class)`, pulls out one `test*` method and runs
it, then inspects a `TestResult`, is the standard way to run one method. The
existing `ImmutableSetTest` methods (`testResizeTable`, `testEquals`,
`testCreation_manyDuplicates`, ...) must stay green after your fix.
