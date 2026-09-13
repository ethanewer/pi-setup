#!/bin/bash
# Verifier for capstan-reach: proves the agent's fix in the real google/guava
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit; every tracked file except the single fixed source file byte-identical
# to it; no stray untracked files), (2) requiring /app/summary.md, (3)
# recompiling the whole library offline from the agent's tree, (4) planting the
# project's OWN regression test for this bug (extracted from the fix commit at
# image build time into /opt/golden) and running it via a JUnit3 harness (on
# the unfixed tree it errors with "length (-1) may not be negative"), (5)
# running the whole fixed-version ByteSourceTest class (the project's own
# existing suite for this API), (6) running the direct reproduction and
# checking its exact output, and (7) running three authored hidden cases that
# reach the same broken code path from inputs the upstream test does not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=931e83f969de433f6f0cad9f09eafe0c1d44325e
CP="/opt/jars/*"
JAVAC="javac -J-Xmx3g"
CLS=/tmp/vcls

IO_TEST_FILES="
guava-tests/test/com/google/common/io/IoTestCase.java
guava-tests/test/com/google/common/io/TestOption.java
guava-tests/test/com/google/common/io/TestByteSource.java
guava-tests/test/com/google/common/io/TestByteSink.java
guava-tests/test/com/google/common/io/AndroidIncompatible.java
guava-tests/test/com/google/common/io/ByteSourceTester.java
guava-tests/test/com/google/common/io/SourceSinkTester.java
guava-tests/test/com/google/common/io/SourceSinkFactory.java
guava-tests/test/com/google/common/io/SourceSinkFactories.java
guava-tests/test/com/google/common/io/TestStreamSupplier.java
guava-tests/test/com/google/common/io/TestInputStream.java
guava-tests/test/com/google/common/io/TestOutputStream.java
guava-tests/test/com/google/common/io/CloserTest.java
guava-tests/test/com/google/common/io/RandomAmountInputStream.java
guava-tests/test/com/google/common/io/CharSourceTester.java
guava-tests/test/com/google/common/io/TestCharSink.java
guava-tests/test/com/google/common/io/TestCharSource.java
guava-tests/test/com/google/common/io/TestReader.java
guava-tests/test/com/google/common/io/TestWriter.java
guava-tests/test/com/google/common/io/CharSinkTester.java
"

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is in
#    (discovered by the agent, not named here), with its android mirror twin
#    also tolerated. CONTENT check: hash the actual bytes of every tracked file
#    on disk against the pinned commit's own blob, and refuse any untracked
#    non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        guava/src/com/google/common/io/ByteSource.java|android/guava/src/com/google/common/io/ByteSource.java) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
            else
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) recompile the whole library from the agent's tree (proves it compiles and
#    incorporates the fix).
rm -rf "$CLS"; mkdir -p "$CLS"
if ! $JAVAC -cp "$CP" -d "$CLS" $(find guava/src -name '*.java') > "$LOG.guava" 2>&1; then
    tail -40 "$LOG.guava" >&2
    fail "guava/src did not compile (see $LOG.guava)"
fi
if ! $JAVAC -cp "$CLS:$CP" -d "$CLS" $(find guava-testlib/src -name '*.java') > "$LOG.testlib" 2>&1; then
    tail -40 "$LOG.testlib" >&2
    fail "guava-testlib/src did not compile (see $LOG.testlib)"
fi

# 5) plant the project's own regression test (golden bytes from /opt/golden,
#    extracted from the fix commit at image build time; never part of this task
#    tree) and compile it plus the io test-support closure and the harnesses.
rm -rf /tmp/gsrc /tmp/gcls; mkdir -p /tmp/gsrc/com/google/common/io /tmp/gcls
cp /opt/golden/ByteSourceTest.java /tmp/gsrc/com/google/common/io/ByteSourceTest.java
if ! $JAVAC -cp "$CLS:$CP" -d /tmp/gcls \
    /tmp/gsrc/com/google/common/io/ByteSourceTest.java \
    $(cd /app/src && echo $IO_TEST_FILES) > "$LOG.golden" 2>&1; then
    tail -40 "$LOG.golden" >&2
    fail "golden test classes did not compile (see $LOG.golden)"
fi

cat > /tmp/GoldenRun.java <<'JAVA'
import com.google.common.io.ByteSourceTest;
import junit.framework.TestCase;
import junit.framework.TestResult;

public class GoldenRun {
  public static void main(String[] args) throws Exception {
    String methodName = "testSlice_returnEmptySource";
    TestCase t = new ByteSourceTest();
    t.setName(methodName);
    TestResult r = new TestResult();
    t.run(r);
    System.out.println("runCount=" + r.runCount() + " failures=" + r.failureCount() + " errors=" + r.errorCount());
    for (int i = 0; i < r.errorCount(); i++) {
      System.out.println("ERROR: " + r.errors().nextElement().exceptionMessage());
    }
    for (int i = 0; i < r.failureCount(); i++) {
      System.out.println("FAIL: " + r.failures().nextElement().exceptionMessage());
    }
    if (r.runCount() > 0 && r.failureCount() == 0 && r.errorCount() == 0) System.exit(0);
    System.exit(1);
  }
}
JAVA
cat > /tmp/SuiteRun.java <<'JAVA'
import com.google.common.io.ByteSourceTest;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import junit.framework.TestCase;
import junit.framework.TestResult;

public class SuiteRun {
  public static void main(String[] args) throws Exception {
    int ran = 0, failed = 0;
    boolean regressionOk = false;
    for (Method m : ByteSourceTest.class.getDeclaredMethods()) {
      if (!m.getName().startsWith("test")) continue;
      if (!Modifier.isPublic(m.getModifiers())) continue;
      if (m.getParameterCount() != 0) continue;
      TestCase t = new ByteSourceTest();
      t.setName(m.getName());
      TestResult r = new TestResult();
      t.run(r);
      boolean ok = r.runCount() > 0 && r.failureCount() == 0 && r.errorCount() == 0;
      System.out.println(m.getName() + " " + (ok ? "ok" : "FAIL"));
      if (!ok) failed++;
      if (m.getName().equals("testSlice_returnEmptySource") && ok) regressionOk = true;
      ran++;
    }
    System.out.println("ran=" + ran + " failed=" + failed);
    System.exit(failed == 0 && ran >= 15 && regressionOk ? 0 : 1);
  }
}
JAVA
cat > /tmp/Reproducer.java <<'JAVA'
import com.google.common.io.ByteSource;
public class Reproducer {
  public static void main(String[] args) throws Exception {
    try {
      ByteSource s = ByteSource.concat().slice(0, 3).slice(4, 3);
      System.out.println("no exception; isEmpty=" + s.isEmpty());
      if (!s.isEmpty()) System.exit(1);
      System.out.println("OK");
    } catch (IllegalArgumentException e) {
      System.out.println("BUG: IllegalArgumentException thrown: " + e.getMessage());
      System.exit(1);
    }
  }
}
JAVA
if ! $JAVAC -cp "$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/GoldenRun.java /tmp/SuiteRun.java /tmp/Reproducer.java > "$LOG.harness" 2>&1; then
    tail -40 "$LOG.harness" >&2
    fail "harness did not compile (see $LOG.harness)"
fi

# 6) the project's own upstream regression test must pass. On the unfixed tree
#    it errors with IllegalArgumentException "length (-1) may not be negative".
if ! timeout 90 java -cp "/tmp/gcls:$CLS:$CP" GoldenRun > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "runCount=1 failures=0 errors=0" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "upstream regression test did not actually run and pass (see /tmp/golden.out)"
}

# 7) the project's own existing suite (whole fixed-version ByteSourceTest class)
#    must stay green and actually run; the regression method must be among the
#    passing methods (SuiteRun exits non-zero otherwise).
if ! timeout 300 java -cp "/tmp/gcls:$CLS:$CP" SuiteRun > /tmp/suite.out 2>&1; then
    tail -30 /tmp/suite.out >&2
    fail "existing ByteSourceTest suite selection failed (see /tmp/suite.out)"
fi
grep -q "failed=0" /tmp/suite.out || {
    tail -20 /tmp/suite.out >&2
    fail "existing suite did not run cleanly (see /tmp/suite.out)"
}

# 8) direct reproduction: must print the exact expected lines and exit 0.
REPRO_EXPECTED='no exception; isEmpty=true
OK'
set +e
timeout 45 java -cp "/tmp/gcls:$CLS:$CP" Reproducer > /tmp/repro.out 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    echo "direct repro exited $rc (expected 0); output:" >> "$LOG"
    tail -10 /tmp/repro.out >> "$LOG"
    fail "direct reproduction did not exit 0 (see $LOG)"
fi
if ! printf '%s\n' "$REPRO_EXPECTED" | cmp -s - /tmp/repro.out; then
    echo "direct repro output mismatch; got:" >> "$LOG"
    cat /tmp/repro.out >> "$LOG"
    fail "direct reproduction output mismatch (see $LOG)"
fi

# 9) hidden cases: other inputs reaching the same code path (non-empty wrapped
#    source, three-level nesting, stream consumption). Compile each and require
#    byte-exact stdout and exit 0. On the unfixed tree every one of them throws
#    IllegalArgumentException ("length (-N) may not be negative").
rm -rf /tmp/hcls; mkdir -p /tmp/hcls
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    src=$(ls "$case"/*.java 2>/dev/null | head -1)
    exp="$case/expected"
    [ -n "$src" ] && [ -f "$exp" ] || fail "hidden case $name: missing .java or expected"
    if ! $JAVAC -cp "$CLS:$CP" -d /tmp/hcls "$src" > "$LOG.$name.build" 2>&1; then
        tail -20 "$LOG.$name.build" >&2
        fail "hidden case $name did not compile (see $LOG.$name.build)"
    fi
    mainclass=$(basename "$src" .java)
    set +e
    timeout 60 java -cp "/tmp/hcls:$CLS:$CP" "$mainclass" > /tmp/hc.out 2> /tmp/hc.err
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stderr:" >> "$LOG"
        head -6 /tmp/hc.err >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    if ! cmp -s /tmp/hc.out "$exp"; then
        echo "hidden case $name: output mismatch; got:" >> "$LOG"
        cat /tmp/hc.out >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, full compile, upstream regression test, existing suite, direct repro, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0