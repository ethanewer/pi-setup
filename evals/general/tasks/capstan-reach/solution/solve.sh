#!/bin/bash
# Oracle for capstan-reach: applies the two-line fix to the real google/guava
# tree at /app/src (SlicedByteSource.slice() must return ByteSource.empty()
# when the requested offset is past the current slice's length, instead of
# recursing with a negative length that trips the public slice() precondition),
# writes /app/summary.md, then proves the work by recompiling the whole library
# and running the project's own regression test (baked at /opt/golden), the
# whole fixed-version ByteSourceTest class, and the direct reproduction, all
# offline. Reads only /app, /solution and /opt/golden, never /tests.
set -u

# --- build the standard compile/run pipeline ---------------------------------
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

run_step() {  # name, command...
  local name=$1; shift
  echo "oracle: $name"
  if ! "$@" > /tmp/oracle.log 2>&1; then
    echo "oracle: $name FAILED (exit $?)" >&2
    tail -40 /tmp/oracle.log >&2
    exit 1
  fi
}

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# 1) apply the fix
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the sliced-source empty-slice fix"

# 2) write the summary deliverable
cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: ByteSource.slice(offset, length) documents that a slice whose start lies
beyond the source is empty, but when the source being sliced is itself already
a slice (SlicedByteSource), and the new offset is past that slice's remaining
length, the nested slice() call recursed with a NEGATIVE length: it computed
min(requestedLength, remainingLength - offset), got a negative number, and the
public slice() precondition checkArgument(length >= 0) threw
IllegalArgumentException ("length (-1) may not be negative"). Defensive code
that re-slices bounded windows past their end crashed instead of receiving the
documented empty source.

Fix: in SlicedByteSource.slice(), when the requested offset is at or past the
current slice's length (maxLength <= 0), return ByteSource.empty() directly
instead of recursing with a negative length. Slices that still overlap the
window behave exactly as before.

Verification: recompiled the whole library from the fixed tree, ran the
project's own regression test for this bug (planted from /opt/golden) via the
JUnit3 harness -> runCount=1 failures=0 errors=0; the whole fixed-version
ByteSourceTest class (the project's own existing suite for this API) runs
green; and the direct reproduction prints 'no exception; isEmpty=true' and
exits 0.
MD
[ -s /app/summary.md ] || { echo "oracle: summary not written" >&2; exit 1; }

# 3) compile guava/src and guava-testlib/src from the fixed tree
rm -rf "$CLS"; mkdir -p "$CLS"
run_step "compile guava/src" $JAVAC -cp "$CP" -d "$CLS" $(find guava/src -name '*.java')
run_step "compile guava-testlib/src" $JAVAC -cp "$CLS:$CP" -d "$CLS" $(find guava-testlib/src -name '*.java')

# 4) compile the golden regression test + the io test-support closure + a tiny
#    JUnit3 harness
rm -rf /tmp/gsrc /tmp/gcls; mkdir -p /tmp/gsrc/com/google/common/io /tmp/gcls
cp /opt/golden/ByteSourceTest.java /tmp/gsrc/com/google/common/io/ByteSourceTest.java
run_step "compile io test support + golden test classes" $JAVAC -cp "$CLS:$CP" -d /tmp/gcls \
    /tmp/gsrc/com/google/common/io/ByteSourceTest.java \
    $(cd /app/src && echo $IO_TEST_FILES)

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
run_step "compile harnesses" $JAVAC -cp "$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/GoldenRun.java /tmp/SuiteRun.java /tmp/Reproducer.java

# 5) run the project's own regression test
run_step "run upstream regression test (single method)" timeout 90 \
    java -cp "/tmp/gcls:$CLS:$CP" GoldenRun
GREPB=$(java -cp "/tmp/gcls:$CLS:$CP" GoldenRun 2>/dev/null | grep -o "runCount=1 failures=0 errors=0" | head -1)
[ "$GREPB" = "runCount=1 failures=0 errors=0" ] || { echo "oracle: regression did not pass" >&2; exit 1; }

# 6) run the whole fixed-version ByteSourceTest class (project's own suite)
run_step "run whole ByteSourceTest class" timeout 300 \
    java -cp "/tmp/gcls:$CLS:$CP" SuiteRun

# 7) run the direct reproduction
run_step "run direct repro" timeout 45 \
    java -cp "/tmp/gcls:$CLS:$CP" Reproducer
set +e
timeout 45 java -cp "/tmp/gcls:$CLS:$CP" Reproducer > /tmp/oracle_repro.out 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] && grep -q "no exception; isEmpty=true" /tmp/oracle_repro.out && grep -q "^OK$" /tmp/oracle_repro.out || {
    echo "oracle: direct reproduction failed rc=$rc" >&2
    tail -10 /tmp/oracle_repro.out >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression+suite+repro all green"
exit 0