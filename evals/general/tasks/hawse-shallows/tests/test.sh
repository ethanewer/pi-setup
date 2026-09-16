#!/bin/bash
# Verifier for hawse-shallows: proves the agent's fix in the real google/guava
# tree at /app/src. Pipeline:
#  (1) provenance: HEAD still the pinned parent commit; every tracked file
#      except the single fixed source file byte-identical to it; no untracked
#      files in the tree;
#  (2) deliverables: /app/repro/SplitRepro.java (the agent's OWN
#      self-checking reproduction) and /app/summary.md exist;
#  (3) builds a PRISTINE pre-fix class tree from the pinned commit (git
#      archive HEAD, which equals the parent because of (1)) and a fixed-tree
#      class tree from /app/src;
#  (4) runs the agent's reproduction in BOTH directions: it must FAIL against
#      the pre-fix tree and PASS against the repaired tree;
#  (5) plants the project's OWN regression test for this bug (extracted from
#      the fix commit at image build time into /opt/golden, sha256-verified
#      against the fix commit's bytes) and runs both regression methods;
#  (6) runs 12 of the project's own existing SplitterTest methods;
#  (7) runs four authored hidden cases whose inputs and pattern classes the
#      upstream regression test does not use, each asserted in BOTH
#      directions: must fail pre-fix and pass post-fix with byte-exact output.
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

PARENT=5367a2d0687ec4c1901f693559cd4d2d14ca65d1
# The project's own regression test for this bug is extracted from the UPSTREAM
# FIX COMMIT at image build time into /opt/golden. The trial container may run
# as root, so /opt/golden is writable during the agent phase; assert at trial
# time that those bytes are still the fix commit's, or an agent could replace
# the regression test with trivial fakes and only the repro + hidden cases
# would still be measuring anything. These constants are the sha256 of the two
# files AT THE FIX COMMIT (git show <fix>:<path> | sha256sum), computed against
# the upstream repository when the task was authored.
GOLDEN_SHA_SPLITTERTEST=60ef8bc2aa896bcb12bcfe5fdbcccb757e6d6055d93a21eba689472cdfc632fe
GOLDEN_SHA_ANDROIDINCOMPATIBLE=bf9067a15280aee6d2c0098a4fb518e35b77a1516c55cb8c7511e737cb195096
CP="/opt/jars/*"
JAVAC="javac -J-Xmx3g"
CLS=/tmp/cls
PCLS=/tmp/pcls
TCLS=/tmp/tcls

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
        guava/src/com/google/common/base/Splitter.java) : ;;
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

# 3) deliverables: the agent's OWN reproduction and change summary.
[ -s /app/repro/SplitRepro.java ] || fail "/app/repro/SplitRepro.java is missing or empty"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -q "Splitter" /app/repro/SplitRepro.java || fail "/app/repro/SplitRepro.java does not exercise Splitter"
grep -q "exit" /app/repro/SplitRepro.java || fail "/app/repro/SplitRepro.java has no exit contract"

# 4) two class trees: PRISTINE pre-fix (from the pinned commit) and the agent's
#    repaired /app/src.
rm -rf /tmp/prefix "$PCLS" "$CLS" "$TCLS"; mkdir -p /tmp/prefix "$PCLS" "$CLS" "$TCLS"
if ! git archive HEAD | tar -x -C /tmp/prefix; then
    fail "could not materialise the pre-fix tree from the pinned commit"
fi
if ! $JAVAC -cp "$CP" -d "$PCLS" $(find /tmp/prefix/guava/src -name '*.java') > "$LOG.pclsb" 2>&1; then
    tail -40 "$LOG.pclsb" >&2
    fail "pre-fix guava/src did not compile (see $LOG.pclsb)"
fi
if ! $JAVAC -cp "$CP" -d "$CLS" $(find guava/src -name '*.java') > "$LOG.clsb" 2>&1; then
    tail -40 "$LOG.clsb" >&2
    fail "fixed guava/src did not compile (see $LOG.clsb)"
fi
if ! $JAVAC -cp "$CLS:$CP" -d "$TCLS" $(find guava-testlib/src -name '*.java') > "$LOG.tclsb" 2>&1; then
    tail -40 "$LOG.tclsb" >&2
    fail "guava-testlib/src did not compile (see $LOG.tclsb)"
fi

# 5) the agent's reproduction in BOTH directions. It must compile against both
#    class trees (public API only) and then: FAIL (non-zero exit) against the
#    pre-fix tree and PASS (exit 0) against the repaired tree.
rm -rf /tmp/prcls /tmp/rcls; mkdir -p /tmp/prcls /tmp/rcls
if ! $JAVAC -cp "$PCLS:$CP" -d /tmp/prcls /app/repro/SplitRepro.java > "$LOG.repropb" 2>&1; then
    tail -20 "$LOG.repropb" >&2
    fail "reproduction does not compile against the pre-fix library (see $LOG.repropb)"
fi
if ! $JAVAC -cp "$CLS:$CP" -d /tmp/rcls /app/repro/SplitRepro.java > "$LOG.reprocb" 2>&1; then
    tail -20 "$LOG.reprocb" >&2
    fail "reproduction does not compile against the fixed library (see $LOG.reprocb)"
fi
set +e
timeout 60 java -cp "/tmp/prcls:$PCLS:$CP" SplitRepro > /tmp/repro.pristine.out 2>&1
prc=$?
timeout 60 java -cp "/tmp/rcls:$CLS:$CP" SplitRepro > /tmp/repro.fixed.out 2>&1
frc=$?
set -e
if [ "$prc" -eq 0 ]; then
    echo "reproduction PASSED on the pre-fix tree (should have failed):" >> "$LOG"
    cat /tmp/repro.pristine.out >> "$LOG"
    fail "reproduction did not actually fail before the fix (see $LOG)"
fi
if [ "$frc" -ne 0 ]; then
    echo "reproduction FAILED on the fixed tree (stderr/out):" >> "$LOG"
    cat /tmp/repro.fixed.out >> "$LOG"
    tail -20 /tmp/repro.fixed.out >&2
    fail "reproduction does not pass after the fix (see /tmp/repro.fixed.out)"
fi

# 6) plant the project's own regression test (golden bytes from /opt/golden,
#    extracted from the fix commit at image build time; never part of this task
#    tree) and compile it plus the JUnit3 harness. First prove the golden bytes
#    are still the fix commit's: the image may be writable as root during the
#    trial.
sha256sum /opt/golden/SplitterTest.java > /tmp/golden.sha
read -r GOT_SHA _ < /tmp/golden.sha
[ "$GOT_SHA" = "$GOLDEN_SHA_SPLITTERTEST" ] || {
    tail -3 /tmp/golden.sha >&2
    fail "golden SplitterTest.java does not match the upstream fix commit (tampered?)"
}
sha256sum /opt/golden/AndroidIncompatible.java > /tmp/goldenai.sha
read -r GOT_SHA _ < /tmp/goldenai.sha
[ "$GOT_SHA" = "$GOLDEN_SHA_ANDROIDINCOMPATIBLE" ] || {
    tail -3 /tmp/goldenai.sha >&2
    fail "golden AndroidIncompatible.java does not match the upstream fix commit (tampered?)"
}
rm -rf /tmp/gsrc /tmp/gcls; mkdir -p /tmp/gsrc /tmp/gcls
cp /opt/golden/SplitterTest.java /opt/golden/AndroidIncompatible.java /tmp/gsrc/
if ! $JAVAC -cp "$TCLS:$CLS:$CP" -d /tmp/gcls \
    /tmp/gsrc/SplitterTest.java /tmp/gsrc/AndroidIncompatible.java > "$LOG.goldenb" 2>&1; then
    tail -40 "$LOG.goldenb" >&2
    fail "golden test classes did not compile (see $LOG.goldenb)"
fi

cat > /tmp/RunBatch.java <<'JAVA'
import junit.framework.Test;
import junit.framework.TestResult;
import junit.framework.TestSuite;
import com.google.common.base.SplitterTest;

public class RunBatch {
  static final String[] GOLDEN = {
    "testPatternSplitWordBoundary_singleCharInput",
    "testPatternSplitWordBoundary_singleWordInput",
  };
  static final String[] EXISTING = {
    "testPatternSimpleSplit", "testPatternSimpleSplitWithNoDelimiter", "testPatternSplitLookBehind",
    "testPatternSplitMatchingIsGreedy", "testPatternSplitWordBoundary", "testPatternSplitWithMultipleLetters",
    "testPatternSplitWithTrailingDelimiter", "testFixedLengthSplitIntoChars", "testCharacterSplitWithMatcherDelimiter",
    "testStringSimpleSplit", "testLimitOne", "testToString",
  };
  public static void main(String[] args) throws Exception {
    String[] want = args[0].equals("golden") ? GOLDEN : EXISTING;
    TestSuite suite = new TestSuite(SplitterTest.class);
    int ran = 0, failed = 0;
    for (int i = 0; i < suite.testCount(); i++) {
      String n = suite.testAt(i).toString();
      for (String m : want) {
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
    System.exit(failed == 0 && ran == want.length ? 0 : 1);
  }
}
JAVA
if ! $JAVAC -cp "$TCLS:$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/RunBatch.java > "$LOG.harnessb" 2>&1; then
    tail -40 "$LOG.harnessb" >&2
    fail "harness did not compile (see $LOG.harnessb)"
fi

# 7) the project's own upstream regression test must pass on the repaired tree.
if ! timeout 180 java -cp "/tmp/gcls:$TCLS:$CLS:$CP" RunBatch golden > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "ran=2 failed=0" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "upstream regression test did not actually run and pass (see /tmp/golden.out)"
}

# 8) the project's own existing suite selection must stay green and run.
if ! timeout 300 java -cp "/tmp/gcls:$TCLS:$CLS:$CP" RunBatch existing > /tmp/suite.out 2>&1; then
    tail -30 /tmp/suite.out >&2
    fail "existing SplitterTest selection failed (see /tmp/suite.out)"
fi
grep -q "ran=12 failed=0" /tmp/suite.out || {
    tail -20 /tmp/suite.out >&2
    fail "existing suite did not run all 12 methods cleanly (see /tmp/suite.out)"
}

# 9) authored hidden cases: other zero-width-pattern inputs reaching the same
#    code path. Each must PASS (exit 0, byte-exact stdout) against the repaired
#    tree AND must NOT pass against the pre-fix tree.
rm -rf /tmp/hcls /tmp/hpcls; mkdir -p /tmp/hcls /tmp/hpcls
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    src=$(ls "$case"/*.java 2>/dev/null | head -1)
    exp="$case/expected"
    mainclass=$(basename "$src" .java)
    [ -n "$src" ] && [ -f "$exp" ] || fail "hidden case $name: missing .java or expected"
    if ! $JAVAC -cp "$CLS:$CP" -d /tmp/hcls "$src" > "$LOG.$name.build" 2>&1; then
        tail -20 "$LOG.$name.build" >&2
        fail "hidden case $name did not compile against fixed tree (see $LOG.$name.build)"
    fi
    if ! $JAVAC -cp "$PCLS:$CP" -d /tmp/hpcls "$src" > "$LOG.$name.pbuild" 2>&1; then
        tail -20 "$LOG.$name.pbuild" >&2
        fail "hidden case $name did not compile against pre-fix tree (see $LOG.$name.pbuild)"
    fi
    set +e
    timeout 60 java -cp "/tmp/hcls:$CLS:$CP" "$mainclass" > /tmp/hc.out 2> /tmp/hc.err
    rc=$?
    timeout 60 java -cp "/tmp/hpcls:$PCLS:$CP" "$mainclass" > /tmp/hcp.out 2> /tmp/hcp.err
    prc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc on the fixed tree (expected 0); stderr:" >> "$LOG"
        head -6 /tmp/hc.err >> "$LOG"
        fail "hidden case $name: exited $rc on the fixed tree (see $LOG)"
    fi
    if ! cmp -s /tmp/hc.out "$exp"; then
        echo "hidden case $name: output mismatch on the fixed tree; got:" >> "$LOG"
        cat /tmp/hc.out >> "$LOG"
        fail "hidden case $name: output mismatch on the fixed tree (see $LOG)"
    fi
    if [ "$prc" -eq 0 ] && cmp -s /tmp/hcp.out "$exp"; then
        echo "hidden case $name: passed on the PRE-FIX tree too (not discriminating)" >> "$LOG"
        cat /tmp/hcp.out >> "$LOG"
        fail "hidden case $name did not fail pre-fix (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, deliverables, pre-fix/fixed tree compiles, bidirectional repro, golden regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0