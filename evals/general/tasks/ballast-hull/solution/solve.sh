#!/bin/bash
# Oracle for ballast-hull: applies the two-line fix to the real google/guava
# tree at /app/src (in RegularSetBuilderImpl.review(), reset maxRunBeforeFallback
# and expandTableThreshold after the table is shrunk), writes /app/summary.md,
# then proves the work by recompiling the whole library and running the project's
# own regression test (baked at /opt/golden) and a selection of the project's own
# existing ImmutableSetTest methods plus the direct reproduction, all offline.
# Reads only /app, /solution and /opt/golden, never /tests.
set -u

# --- build the standard compile/run pipeline ---------------------------------
CP="/opt/jars/*"
JAVAC="javac -J-Xmx3g"
CLS=/tmp/vcls

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
echo "oracle: applied the review() table-reshape fix"

# 2) write the summary deliverable
cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: an ImmutableSet.Builder created with an expected size can be reused to
build more than one set, but the first build() resized the builder's internal
open-addressed hash table to its current contents while leaving the table's
bookkeeping values (maxRunBeforeFallback and expandTableThreshold) sized for the
original, much larger table. Adding more elements to the reused builder then
fills that small table to 100%; because the probe bound still assumes a large
table, a contains() query on the resulting set probes past every slot forever,
or (other element counts) silently drops/misreports elements.

Fix: in RegularSetBuilderImpl.review(), after the table is shrunk via
rebuildHashTable, also recompute maxRunBeforeFallback and expandTableThreshold
from the new table size (the same two assignments ensureTableCapacity already
makes when the table GROWS). With correct thresholds the reused builder grows the
table before it can fill, so every membership query terminates and returns the
right answer. This changes only the single source file where the bug lives and
leaves every other code path untouched.

Verification: recompiled the whole library from the fixed tree, ran the project's
own regression test for this bug (planted from /opt/golden) via the JUnit3
harness -> runCount=1 failures=0 errors=0; the direct reproduction prints
'contains(4)=false subject=[0, 1, 2, 3]' and exits 0; and 12 of the project's own
existing ImmutableSetTest methods all pass.
MD
[ -s /app/summary.md ] || { echo "oracle: summary not written" >&2; exit 1; }

# 3) compile guava/src and guava-testlib/src from the fixed tree
rm -rf "$CLS"; mkdir -p "$CLS"
run_step "compile guava/src" $JAVAC -cp "$CP" -d "$CLS" $(find guava/src -name '*.java')
run_step "compile guava-testlib/src" $JAVAC -cp "$CLS:$CP" -d "$CLS" $(find guava-testlib/src -name '*.java')

# 4) compile the golden regression test + a tiny JUnit3 harness
rm -rf /tmp/gsrc /tmp/gcls; mkdir -p /tmp/gsrc/com/google/common/collect /tmp/gcls
cp /opt/golden/ImmutableSetTest.java /tmp/gsrc/com/google/common/collect/ImmutableSetTest.java
cp /opt/golden/AbstractImmutableSetTest.java /tmp/gsrc/com/google/common/collect/AbstractImmutableSetTest.java
run_step "compile golden test classes" $JAVAC -cp "$CLS:$CP" -d /tmp/gcls \
    /tmp/gsrc/com/google/common/collect/ImmutableSetTest.java \
    /tmp/gsrc/com/google/common/collect/AbstractImmutableSetTest.java

cat > /tmp/GoldenRun.java <<'JAVA'
import junit.framework.Test;
import junit.framework.TestResult;
import junit.framework.TestSuite;
import com.google.common.collect.ImmutableSetTest;

public class GoldenRun {
  public static void main(String[] args) throws Exception {
    String methodName = "testReuseBuilderReducingHashTableSizeWithPowerOfTwoTotalElements";
    TestSuite suite = new TestSuite(ImmutableSetTest.class);
    Test target = null;
    for (int i = 0; i < suite.testCount(); i++) {
      if (suite.testAt(i).toString().startsWith(methodName + "(")) { target = suite.testAt(i); break; }
    }
    if (target == null) { System.out.println("METHOD_NOT_FOUND"); System.exit(2); }
    TestResult r = new TestResult();
    target.run(r);
    System.out.println("runCount=" + r.runCount() + " failures=" + r.failureCount() + " errors=" + r.errorCount());
    if (r.runCount() > 0 && r.failureCount() == 0 && r.errorCount() == 0) System.exit(0);
    System.exit(1);
  }
}
JAVA
cat > /tmp/SuiteRun.java <<'JAVA'
import junit.framework.Test;
import junit.framework.TestResult;
import junit.framework.TestSuite;
import com.google.common.collect.ImmutableSetTest;

public class SuiteRun {
  static final String[] METHODS = {
    "testCreation_allDuplicates", "testCreation_oneDuplicate", "testCreation_manyDuplicates",
    "testChooseTableSize", "testResizeTable", "testCopyOf_threadSafe",
    "testToImmutableSet", "testToImmutableSet_duplicates", "testCopyOf_copiesImmutableSortedSet",
    "testEquals", "testResistsHashFloodingInConstruction", "testResistsHashFloodingOnContains",
  };
  public static void main(String[] args) throws Exception {
    TestSuite suite = new TestSuite(ImmutableSetTest.class);
    int ran = 0, failed = 0;
    for (int i = 0; i < suite.testCount(); i++) {
      String n = suite.testAt(i).toString();
      for (String m : METHODS) {
        if (n.startsWith(m + "(")) {
          TestResult r = new TestResult();
          suite.testAt(i).run(r);
          boolean ok = r.runCount() > 0 && r.failureCount() == 0 && r.errorCount() == 0;
          System.out.println(m + " " + (ok ? "ok" : "FAIL"));
          if (!ok) failed++;
          ran++;
        }
      }
    }
    System.out.println("ran=" + ran + " failed=" + failed);
    System.exit(failed == 0 && ran == METHODS.length ? 0 : 1);
  }
}
JAVA
run_step "compile harnesses" $JAVAC -cp "$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/GoldenRun.java /tmp/SuiteRun.java

# 5) run the project's own regression test (unfixed tree hangs here -> timeout)
run_step "run upstream regression test (single method)" timeout 90 \
    java -cp "/tmp/gcls:$CLS:$CP" GoldenRun
GREPB=$(java -cp "/tmp/gcls:$CLS:$CP" GoldenRun 2>/dev/null | grep -o "runCount=1 failures=0 errors=0" | head -1)
[ "$GREPB" = "runCount=1 failures=0 errors=0" ] || { echo "oracle: regression did not pass" >&2; exit 1; }

# 6) run the selection of the project's own existing tests
run_step "run existing ImmutableSetTest selection" timeout 300 \
    java -cp "/tmp/gcls:$CLS:$CP" SuiteRun

# 7) run the direct reproduction
cat > /tmp/Reproducer.java <<'JAVA'
import com.google.common.collect.ImmutableSet;
public class Reproducer {
  public static void main(String[] args) {
    ImmutableSet.Builder<Object> b = ImmutableSet.builderWithExpectedSize(6);
    b.add(0);
    b.build();
    ImmutableSet<Object> subject = b.add(1).add(2).add(3).build();
    boolean c = subject.contains(4);
    System.out.println("contains(4)=" + c + " subject=" + subject);
    if (c) System.exit(1);
    System.out.println("OK");
  }
}
JAVA
run_step "compile direct repro" $JAVAC -cp "$CLS:$CP" -d "$CLS" /tmp/Reproducer.java
set +e
timeout 45 java -cp "$CLS:$CP" Reproducer > /tmp/oracle_repro.out 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] && grep -q "contains(4)=false subject=\[0, 1, 2, 3\]" /tmp/oracle_repro.out || {
    echo "oracle: direct reproduction failed rc=$rc" >&2
    tail -10 /tmp/oracle_repro.out >&2
    exit 1
}

echo "oracle: fix applied, summary written, regression+suite+repro all green"
exit 0
