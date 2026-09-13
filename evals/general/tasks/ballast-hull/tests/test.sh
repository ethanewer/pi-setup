#!/bin/bash
# Verifier for ballast-hull: proves the agent's fix in the real google/guava
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit; every tracked file except the single fixed source file byte-identical
# to it; no stray untracked files), (2) requiring /app/summary.md, (3)
# recompiling the whole library offline from the agent's tree, (4) planting the
# project's OWN regression test for this bug (extracted from the fix commit at
# image build time into /opt/golden) and running it under a timeout via a JUnit3
# harness (on the unfixed tree it hangs), (5) running 12 of the project's own
# existing ImmutableSetTest methods, (6) running the direct reproduction under a
# timeout and checking its exact output, and (7) running three authored hidden
# cases that reach the same broken code path from inputs the upstream test does
# not use.
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

PARENT=7ab65d08c22fa95adb987d3b3849e5cab60a1c72
# The project's own regression test for this bug is extracted from the UPSTREAM
# FIX COMMIT at image build time into /opt/golden. The trial container runs as
# root, so /opt/golden is writable during the agent phase; assert at trial time
# that those bytes are still the fix commit's, or an agent could replace the
# regression test (and the 12-method selection, which compiles from the same
# files) with trivial fakes and only the direct repro + hidden cases would
# still be measuring anything. These constants are the sha256 of the two files
# AT THE FIX COMMIT (git show <fix>:<path> | sha256sum), computed against the
# upstream repository when the task was authored.
GOLDEN_SHA_IMMUTABLESETTEST=b31d1afdd9d8479971eeaec24c6e393ec218c0ebf55be3b75837ba96e0f7668c
GOLDEN_SHA_ABSTRACTIMMUTABLESETTEST=1c38f96cccbd16563cc6a18a0248d587ec2b98bc509a79627f346c85d789204a
CP="/opt/jars/*"
JAVAC="javac -J-Xmx3g"
CLS=/tmp/vcls

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is in
#    (discovered by the agent, not named here). CONTENT check: hash the actual
#    bytes of every tracked file on disk against the pinned commit's own blob,
#    and refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        guava/src/com/google/common/collect/ImmutableSet.java) : ;;
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
#    tree) and compile it plus the harnesses. First prove the golden bytes are
#    still the fix commit's: the image is writable as root during the trial.
sha256sum /opt/golden/ImmutableSetTest.java > /tmp/golden.set.sha
sha256sum /opt/golden/AbstractImmutableSetTest.java > /tmp/golden.abstract.sha
read -r GOT_SHA _ < /tmp/golden.set.sha
[ "$GOT_SHA" = "$GOLDEN_SHA_IMMUTABLESETTEST" ] || {
    tail -3 /tmp/golden.set.sha >&2
    fail "golden ImmutableSetTest.java does not match the upstream fix commit (tampered?)"
}
read -r GOT_SHA _ < /tmp/golden.abstract.sha
[ "$GOT_SHA" = "$GOLDEN_SHA_ABSTRACTIMMUTABLESETTEST" ] || {
    tail -3 /tmp/golden.abstract.sha >&2
    fail "golden AbstractImmutableSetTest.java does not match the upstream fix commit (tampered?)"
}
rm -rf /tmp/gsrc /tmp/gcls; mkdir -p /tmp/gsrc/com/google/common/collect /tmp/gcls
cp /opt/golden/ImmutableSetTest.java /tmp/gsrc/com/google/common/collect/ImmutableSetTest.java
cp /opt/golden/AbstractImmutableSetTest.java /tmp/gsrc/com/google/common/collect/AbstractImmutableSetTest.java
if ! $JAVAC -cp "$CLS:$CP" -d /tmp/gcls \
    /tmp/gsrc/com/google/common/collect/ImmutableSetTest.java \
    /tmp/gsrc/com/google/common/collect/AbstractImmutableSetTest.java > "$LOG.golden" 2>&1; then
    tail -40 "$LOG.golden" >&2
    fail "golden test classes did not compile (see $LOG.golden)"
fi

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
if ! $JAVAC -cp "$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/GoldenRun.java /tmp/SuiteRun.java /tmp/Reproducer.java > "$LOG.harness" 2>&1; then
    tail -40 "$LOG.harness" >&2
    fail "harness did not compile (see $LOG.harness)"
fi

# 6) the project's own upstream regression test must pass under a timeout. On
#    the unfixed tree this method HANGS; the timeout turns that into a failure.
if ! timeout 90 java -cp "/tmp/gcls:$CLS:$CP" GoldenRun > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass / timed out (see /tmp/golden.out)"
fi
grep -q "runCount=1 failures=0 errors=0" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "upstream regression test did not actually run and pass (see /tmp/golden.out)"
}

# 7) the project's own existing suite selection must stay green and actually run.
if ! timeout 300 java -cp "/tmp/gcls:$CLS:$CP" SuiteRun > /tmp/suite.out 2>&1; then
    tail -30 /tmp/suite.out >&2
    fail "existing ImmutableSetTest selection failed (see /tmp/suite.out)"
fi
grep -q "ran=12 failed=0" /tmp/suite.out || {
    tail -20 /tmp/suite.out >&2
    fail "existing suite did not run all 12 methods cleanly (see /tmp/suite.out)"
}

# 8) direct reproduction: must print the exact expected lines and exit 0.
REPRO_EXPECTED='contains(4)=false subject=[0, 1, 2, 3]
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

# 9) hidden cases: other inputs reaching the same code path. Compile each and
#    require byte-exact stdout and exit 0.
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
