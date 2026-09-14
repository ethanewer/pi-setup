#!/bin/bash
# Verifier for deadwood-shoal: an upstream-clone debugging task on
# apache/commons-lang (LANG-1828: StringUtils.leftPad / rightPad kill the JVM
# with OutOfMemoryError instead of no-op'ing when the requested size is in the
# overflow band around Integer.MIN_VALUE).
#
# The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, and the
#      working tree differs from the pinned commit in exactly one library
#      source file (StringUtils.java), which must actually differ;
#   1. compiles and runs the AGENT's own reproduction /app/repro/PadRepro.java
#      against the pre-fix class snapshot /opt/prefix-classes (heap-capped
#      with -Xmx256m): it must FAIL (non-zero exit) - i.e. the reproduction
#      genuinely demonstrates the bug - and then against the classes Maven
#      rebuilds from the repaired tree: it must PASS (exit 0);
#   2. overlays the upstream FIX's own regression test (kept byte-identical in
#      /opt/golden) and runs the project's own suite for StringUtilsTest
#      through Maven/Surefire after deleting target/classes, so the tree's
#      sources are what is compiled and run: Tests run: 173, Failures: 0,
#      Errors: 0, and the six golden regression methods (the Integer.MIN_VALUE
#      asserts) are each present in the surefire XML with no failure/error;
#   3. compiles and runs two authored hidden cases exercising the same code
#      path from inputs the upstream test does not use: an overflow-band sweep
#      (many string lengths x both pad kinds) and exact boundary sizes with
#      unicode / embedded-NUL / null / empty-padStr inputs.  Each must pass
#      against the repaired classes AND must fail against the pre-fix classes
#      (so they discriminate, not just exist).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=170e9f28ad2667a9b0c80480c2a5a13cb4a53257
FIX_SHA=ae85262f04df19b6307de18758cfdcc31cae733d
GOLDEN=/opt/golden/StringUtilsTest.java
GOLDEN_SHA=b88cc61c00b97295d7b76158dd4c5283db0e9363fd0a6874a36b5cc1bbad561f
PREFIX=/opt/prefix-classes
JAVAHEAP=-Xmx256m
SKIPS="-Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true"
GOLDEN_METHODS="testLeftPad_StringInt testLeftPad_StringIntChar testLeftPad_StringIntString testRightPad_StringInt testRightPad_StringIntChar testRightPad_StringIntString"

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_java() {  # run_java CLASS_DIR DRIVER_CLASS [extra...]
  java $JAVAHEAP -cp "$1:$2" "$3" ${4+"$4"}
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -n "$(git -C "$SRC" show-ref 2>/dev/null)" ]; then
  fail "the clone has refs (an extra commit such as the live default-branch tip could expose the fixed source)"
else
  echo "ok: the clone has no refs; only the pinned parent commit exists"
fi

if [ -z "$(git -C "$SRC" diff --stat -- src/main/java/org/apache/commons/lang3/StringUtils.java 2>/dev/null || true)" ]; then
  fail "StringUtils.java is unchanged (no fix was implemented)"
else
  echo "ok: the library source differs from the pinned commit"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M src/main/java/org/apache/commons/lang3/StringUtils.java"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit in exactly the one library source file"
else
  fail "unexpected working-tree state (expected exactly '$expected'):"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. the agent's own reproduction -----------------------------------
echo "== agent reproduction /app/repro/PadRepro.java =="
if [ ! -f /app/repro/PadRepro.java ]; then
  fail "deliverable /app/repro/PadRepro.java is missing"
else
  mkdir -p /tmp/repro-classes
  if ! javac -cp "$PREFIX" -d /tmp/repro-classes /app/repro/PadRepro.java \
        > /tmp/repro-compile.log 2>&1; then
    fail "the reproduction does not compile against the module classes"
    tail -12 /tmp/repro-compile.log | sed 's/^/    /' >&2
  else
    echo "ok: reproduction compiles"
    if run_java "$PREFIX" /tmp/repro-classes PadRepro > /tmp/repro-prefix.log 2>&1; then
      fail "the reproduction PASSED against the pre-fix classes - it does not demonstrate the bug"
    else
      echo "ok: reproduction FAILS against the pre-fix classes (exit $?)"
      tail -3 /tmp/repro-prefix.log | sed 's/^/    /' >&2 || true
    fi
  fi
fi

# ---------- 2. golden regression test + the project's own suite ---------------
echo "== upstream regression test + StringUtilsTest suite =="
if [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  fail "golden file /opt/golden/StringUtilsTest.java does not match its pinned hash"
else
  echo "ok: golden file hash matches"
  cp "$GOLDEN" "$SRC/src/test/java/org/apache/commons/lang3/StringUtilsTest.java"
  if [ "$(sha256sum "$SRC/src/test/java/org/apache/commons/lang3/StringUtilsTest.java" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    fail "could not overlay the golden test file"
  fi
fi

if [ "$reward" = 1 ]; then
  rm -rf "$SRC/target/classes" "$SRC/target/test-classes" "$SRC/target/surefire-reports"
  if ( cd "$SRC" && mvn -B test -Dtest='StringUtilsTest' -DfailIfNoTests=false $SKIPS ) \
        > /tmp/suite.log 2>&1; then
    echo "ok: Maven run of StringUtilsTest exited 0"
  else
    fail "Maven run of StringUtilsTest failed"
    tail -25 /tmp/suite.log | sed 's/^/    /' >&2 || true
  fi
fi

if [ "$reward" = 1 ]; then
  if grep -q "Tests run: 173, Failures: 0, Errors: 0" /tmp/suite.log; then
    echo "ok: Tests run: 173, Failures: 0, Errors: 0"
  else
    fail "suite summary line is not 'Tests run: 173, Failures: 0, Errors: 0'"
    grep "Tests run:" /tmp/suite.log | sed 's/^/    /' >&2 || true
  fi
fi

xml="$SRC/target/surefire-reports/TEST-org.apache.commons.lang3.StringUtilsTest.xml"
if [ "$reward" = 1 ]; then
  if [ ! -f "$xml" ]; then
    fail "surefire report $xml not found"
  else
    echo "ok: surefire report present"
    for m in $GOLDEN_METHODS; do
      if grep -q "name=\"$m\"" "$xml"; then
        echo "ok: golden regression method $m ran"
      else
        fail "golden regression method $m did not run"
      fi
    done
    if grep -q "<failure\|<error " "$xml"; then
      fail "surefire report contains failures or errors"
      grep -c "<failure\|<error " "$xml" | sed 's/^/    failing /' >&2
    else
      echo "ok: no failures or errors in the surefire report"
    fi
  fi
fi

# ---------- reproduction against the repaired tree ----------------------------
echo "== agent reproduction against the repaired tree =="
if [ "$reward" = 1 ]; then
  if run_java "$SRC/target/classes" /tmp/repro-classes PadRepro > /tmp/repro-fixed.log 2>&1; then
    echo "ok: reproduction PASSES against the repaired classes"
  else
    fail "the reproduction FAILED against the repaired classes"
    tail -8 /tmp/repro-fixed.log | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 3. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  for f in "$case"*.java; do
    [ -f "$f" ] || continue
    cls=$(basename "$f" .java)
    d="/tmp/hidden-$cname"
    mkdir -p "$d"
    if ! javac -cp "$PREFIX" -d "$d" "$f" > "/tmp/cc-$cname.log" 2>&1; then
      fail "hidden case $cname ($cls) did not compile"
      tail -12 "/tmp/cc-$cname.log" | sed 's/^/    /' >&2
      continue
    fi
    if run_java "$SRC/target/classes" "$d" "$cls" > "/tmp/h-$cname-fixed.log" 2>&1; then
      out=$(tail -1 "/tmp/h-$cname-fixed.log")
      echo "ok: hidden case $cname passes the repaired tree: $out"
    else
      fail "hidden case $cname FAILED against the repaired tree"
      tail -6 "/tmp/h-$cname-fixed.log" | sed 's/^/    /' >&2 || true
      continue
    fi
    if run_java "$PREFIX" "$d" "$cls" > /tmp/h-prefix.log 2>&1; then
      fail "hidden case $cname PASSED against the pre-fix classes - it does not discriminate"
    else
      echo "ok: hidden case $cname fails the pre-fix classes (exit $?)"
      tail -2 /tmp/h-prefix.log | sed 's/^/    /' >&2 || true
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0