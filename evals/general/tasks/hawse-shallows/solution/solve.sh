#!/bin/bash
# Oracle for hawse-shallows: applies the one-line upstream fix to the real
# google/guava tree at /app/src (relaxing the zero-width-match iteration stop
# in PatternSplitter so a match exactly at end-of-string no longer drops the
# final piece), writes /app/summary.md, installs /app/repro/SplitRepro.java
# (the self-checking reproduction, shipped from /solution), then proves the
# work by recompiling the whole library and running the project's own
# regression test (baked at /opt/golden), a selection of the project's own
# existing SplitterTest methods, and the reproduction in BOTH directions:
# the repro must FAIL against a pristine pre-fix class tree and PASS against
# the fixed tree. Reads only /app, /solution and /opt/golden.
set -u

CP="/opt/jars/*"
JAVAC="javac -J-Xmx3g"
CLS=/tmp/cls
PCLS=/tmp/pcls
TCLS=/tmp/tcls

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

# 1) apply the fix and write the deliverables
git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the PatternSplitter end-of-string iteration fix"

mkdir -p /app/repro
cp /solution/SplitRepro.java /app/repro/SplitRepro.java
echo "oracle: installed /app/repro/SplitRepro.java"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Symptom
Splitter.on(Pattern) / onPattern can silently DROP the final piece of the
input when the pattern is capable of zero-width matches (word boundary, or
lookahead/lookbehind). A one-character input split on `\b` returns an EMPTY
iterable instead of the single token, and a longer input split on lookarounds
that match after every occurrence of a character loses its last character. The
pieces that do come back are correct and in order; iteration just stops early.

## Root cause
The iterator in PatternSplitter handles a zero-width separator match by
advancing `offset` by one and re-searching, so consecutive empty matches do not
make progress. When such a zero-width match occurs EXACTLY at the end of the
input, the guarding condition `offset >= toSplit.length()` treated
`offset == length` as "past the end" and stopped the iteration without
emitting the final piece of the current split region - dropping the last
character (or, for a single-token input whose only boundary sits at the very
end, the whole string).

## Fix
In SplittingIterator.computeNext() (guava/src/com/google/common/base/Splitter.java)
the guard is relaxed from `offset >= toSplit.length()` to
`offset > toSplit.length()`. With `offset == length` the iterator still
performs one final separator search, finds no further separator, and emits the
remaining tail of the input as its last piece; `offset > length` (true only
when the zero-width advance has genuinely run past the end) still terminates.
This changes only the one source file and leaves every other code path
untouched.

## Verification
- /app/repro/SplitRepro.java (self-checking reproduction): FAILS against a
  pristine pre-fix class tree (both affected cases printed with the dropped
  token) and PASSES against the fixed tree.
- The project's own regression tests for this bug, extracted from the fix
  commit (SplitterTest#testPatternSplitWordBoundary_singleCharInput and
  _singleWordInput), run 1/1 and 1/1 clean via the JUnit 3 harness.
- 12 of the project's own existing SplitterTest methods all pass unchanged.
MD
[ -s /app/summary.md ] || { echo "oracle: summary not written" >&2; exit 1; }

# 2) compile the library + testlib from the FIXED tree
rm -rf "$CLS" "$TCLS" /tmp/gcls /tmp/gsrc /tmp/rcls /tmp/prcls; mkdir -p "$CLS" "$TCLS"
run_step "compile guava/src (fixed)" $JAVAC -cp "$CP" -d "$CLS" $(find guava/src -name '*.java')
run_step "compile guava-testlib/src" $JAVAC -cp "$CLS:$CP" -d "$TCLS" $(find guava-testlib/src -name '*.java')

# 3) compile the project's own regression test (golden bytes from /opt/golden)
run_step "compile golden SplitterTest" bash -c "
  mkdir -p /tmp/gsrc && cp /opt/golden/SplitterTest.java /opt/golden/AndroidIncompatible.java /tmp/gsrc/
  $JAVAC -cp '$TCLS:$CLS:$CP' -d /tmp/gcls /tmp/gsrc/SplitterTest.java /tmp/gsrc/AndroidIncompatible.java"

# 4) shared JUnit3 harnesses
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
run_step "compile harness" $JAVAC -cp "$TCLS:$CLS:$CP:/tmp/gcls" -d /tmp/gcls /tmp/RunBatch.java

# 5) project's own regression test + existing selection, against the FIXED tree
run_step "run golden regression methods" timeout 180 \
    java -cp "/tmp/gcls:$TCLS:$CLS:$CP" RunBatch golden
run_step "run existing SplitterTest selection" timeout 300 \
    java -cp "/tmp/gcls:$TCLS:$CLS:$CP" RunBatch existing

# 6) the reproduction against the FIXED tree must pass
run_step "compile repro against fixed tree" $JAVAC -cp "$CLS:$CP" -d /tmp/rcls /app/repro/SplitRepro.java
set +e
timeout 60 java -cp "/tmp/rcls:$CLS:$CP" SplitRepro > /tmp/oracle_repro_fixed.out 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] && [ "$(tail -1 /tmp/oracle_repro_fixed.out)" = "OK" ] || {
    echo "oracle: repro did not PASS against the fixed tree (rc=$rc)" >&2
    tail -20 /tmp/oracle_repro_fixed.out >&2
    exit 1
}

# 7) the reproduction must FAIL against a PRISTINE pre-fix class tree built
#    from the pinned commit (proves the repro genuinely captures the bug and
#    the verifier's two-direction contract is satisfiable).
rm -rf /tmp/prefix "$PCLS"; mkdir -p /tmp/prefix "$PCLS"
run_step "archive pristine pre-fix tree" bash -c "git archive HEAD | tar -x -C /tmp/prefix"
run_step "compile pristine guava/src" bash -c "$JAVAC -cp '$CP' -d $PCLS \$(find /tmp/prefix/guava/src -name '*.java')"
run_step "compile repro against pristine tree" $JAVAC -cp "$PCLS:$CP" -d /tmp/prcls /app/repro/SplitRepro.java
set +e
timeout 60 java -cp "/tmp/prcls:$PCLS:$CP" SplitRepro > /tmp/oracle_repro_pristine.out 2>&1
prc=$?
set -e
if [ "$prc" -eq 0 ]; then
    echo "oracle: repro unexpectedly PASSED on the pristine pre-fix tree (rc=$prc)" >&2
    cat /tmp/oracle_repro_pristine.out >&2
    exit 1
fi
grep -q "FAIL" /tmp/oracle_repro_pristine.out || {
    echo "oracle: pristine run did not report the failing cases" >&2
    cat /tmp/oracle_repro_pristine.out >&2
    exit 1
}

echo "oracle: fix applied, deliverables written, regression+suite+two-direction repro green"
exit 0