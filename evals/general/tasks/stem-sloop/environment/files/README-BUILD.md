# Build and test guide (google/guava, pinned historical tree)

The repository is checked out at `/app/src` (detached head, pinned to an
historical commit). Everything below uses **javac directly**; Maven is not
set up in this image.

## Compile the library

All annotation jars are already in `/opt/jars` (they are compile-only
dependencies for the 2022-era sources):

```bash
mkdir -p /tmp/classes
javac -d /tmp/classes -cp "/opt/jars/*" \
  $(find /app/src/guava/src -name '*.java' | sort)
```

This takes about 7 seconds on one core. At the end you have
`com/google/common/graph`, `com/google/common/collect`,
`com/google/common/base`, ... under `/tmp/classes`.

## Run your own small programs

```bash
javac -cp /tmp/classes -d /tmp /tmp/MyProgram.java
java -cp /tmp/classes:/tmp MyProgram
```

## Run the project's own JUnit tests for the graph package

The test-framework jars (junit, hamcrest, truth, truth-java8-extension)
are also in `/opt/jars`. Compile the test library and the graph tests:

```bash
mkdir -p /tmp/testlib /tmp/gtests
javac -d /tmp/testlib -cp "/opt/jars/*:/tmp/classes" \
  $(find /app/src/guava-testlib/src -name '*.java' | sort)
javac -d /tmp/gtests -cp "/opt/jars/*:/tmp/classes:/tmp/testlib" \
  $(find /app/src/guava-tests/test/com/google/common/graph -name '*.java' | sort)
```

Then run a whole class or a single method:

```bash
java -cp "/opt/jars/*:/tmp/classes:/tmp/testlib:/tmp/gtests" \
  org.junit.runner.JUnitCore com.google.common.graph.EndpointPairTest

java -cp "/opt/jars/*:/tmp/classes:/tmp/testlib:/tmp/gtests" \
  org.junit.runner.JUnitCore \
  com.google.common.graph.StandardMutableUndirectedGraphTest
```

A single test method:

```bash
java -cp "/opt/run:/opt/jars/*:/tmp/classes:/tmp/testlib:/tmp/gtests" \
  RunOne com.google.common.graph.EndpointPairTest endpointPair_undirected_contains
```

(That last one is the small `RunOne` helper shipped in the image.)

## Constraints to remember

- The tree at `/app/src` is writable by you, but do not commit, fetch,
  reset, rebase or otherwise modify `.git`: the working tree must stay
  detached at the pinned commit.
- There is no build output inside `/app/src` in a pristine state. Keep
  everything you compile under `/tmp` (or another scratch directory), never
  inside `/app/src` — stray files inside the tree are flagged.
- `cpus = 1`: a full guava/src javac is ~7s, so rebuilds are cheap; the
  JUnit runs are a few seconds.