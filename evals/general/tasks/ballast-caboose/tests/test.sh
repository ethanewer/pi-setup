#!/bin/bash
# Verifier for ballast-caboose: an upstream-clone debugging task on
# apache/commons-lang.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# CharRange.contains(CharRange) mishandles a negated argument whose excluded
# block touches a domain boundary. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      source file is CharRange.java with at least one such modification, a
#      CharRangeTest.java overlay is tolerated only when it is byte-identical
#      to the golden file, and no untracked file appears inside the main
#      package source tree);
#   1. runs the direct reproduction /app/probe.sh (must exit 0);
#   2. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   3. runs the project's own test classes around the utility (CharRangeTest,
#      CharSetTest, and the Range family), proving the fix broke nothing else;
#   4. runs three authored hidden-case files: two exercise the same
#      containment code path from boundary-adjacent negated ranges the
#      upstream test does not use (low-boundary complements and high-boundary
#      complements), and one guards that interior exclusions, negated
#      receivers and mid-domain exclusions are unchanged.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=596269f16d33cd4a20223978c245a15c898c5084
FIX_SHA=1d6ef29ce004309e50bd91e27f0f5e80e1a57a76
GOLDEN=/opt/golden/CharRangeTest.java
MVN=/opt/apache-maven-3.9.9/bin/mvn
# There is no CLI switch to stop maven 3.9 from reading ./.mvn/maven.config
# or $HOME/.mavenrc, so step 0 forbids the .mvn dir outright and run_mvn
# requires surefire reports proving every mvn step actually executed and
# passed tests (skipping tests via .mvn/maven.config / ~/.mavenrc / pom
# properties exits 0 producing no reports; maven.test.failure.ignore exits 0
# leaving Failures>0 in the reports).
MFLAGS="-DfailIfNoTests=false -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true -Dmaven.repo.local=/opt/m2repo"

run_mvn () {  # run_mvn LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  # Fresh reports dir. A stale report left by the image build (or by an
  # earlier step) must not be able to stand in for a run that never
  # happened: mvn exits 0 without producing any report when tests are
  # skipped (maven.test.skip/skipTests/... via .mvn/maven.config,
  # ~/.mavenrc, pom.properties or an env var), so the absence of fresh
  # reports is the evidence of a skipped run and a report with
  # Failures>0/Errors>0 is the evidence of a masked failure
  # (maven.test.failure.ignore).
  rm -rf "$SRC"/target/surefire-reports
  if ( cd "$SRC" && "$MVN" -B -q test "$@" $MFLAGS > "$out" 2>&1 ); then
    found=0; bad=0
    for rep in "$SRC"/target/surefire-reports/*.txt; do
      [ -f "$rep" ] || continue
      found=1
      if ! grep -qE 'Tests run: [1-9][0-9]*' "$rep"; then
        echo "FAIL: $label - $rep shows no executed tests" >&2; bad=1
      fi
      if grep -qE 'Failures: [1-9][0-9]*|Errors: [1-9][0-9]*' "$rep"; then
        echo "FAIL: $label - $rep reports test failures/errors" >&2; bad=1
      fi
    done
    if [ "$found" = 0 ]; then
      echo "FAIL: $label - no surefire reports produced: the test suite was not actually executed" >&2; bad=1
    fi
    if [ "$bad" = 0 ]; then
      echo "ok: $label"
      return 0
    fi
    reward=0
    return 1
  fi
  echo "FAIL: $label" >&2
  for rep in "$SRC"/target/surefire-reports/*.txt; do
    [ -f "$rep" ] && echo "== ${rep##*/} ==" && tail -30 "$rep" | sed 's/^/    /'
  done
  tail -25 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
ok_prov=1
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; ok_prov=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; ok_prov=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  ok_prov=0
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  ok_prov=0
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

if [ -e "$SRC/.mvn" ]; then
  echo "FAIL: an untracked .mvn dir exists in /app/src (gitignored, so invisible to git status; it can inject maven goals/properties such as -Dmaven.test.skip=true)" >&2
  ok_prov=0
else
  echo "ok: no .mvn directory in the working clone"
fi

# assume-unchanged ('h') / skip-worktree ('S') on any tracked file hides its
# working-tree modifications from git status; an agent could otherwise patch
# pom.xml (e.g. maven.test.skip / maven.test.failure.ignore) and hide it.
aux_flag=$(git -C "$SRC" ls-files -v 2>/dev/null | awk '$1 ~ /^[hS]/ {print $1, $2}')
if [ -n "$aux_flag" ]; then
  echo "FAIL: assume-unchanged/skip-worktree flags present on tracked files: $aux_flag" >&2
  ok_prov=0
else
  echo "ok: no hidden working-tree changes (no assume-unchanged/skip-worktree flags)"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M src/main/java/org/apache/commons/lang3/CharRange.java")
      saw_mod=1
      ;;
    " M src/test/java/org/apache/commons/lang3/CharRangeTest.java")
      # benign only if it is byte-identical to the golden regression test
      if [ -f "$GOLDEN" ] && cmp -s "$SRC/src/test/java/org/apache/commons/lang3/CharRangeTest.java" "$GOLDEN"; then
        echo "note: CharRangeTest.java is a benign overlay of the golden regression test"
      else
        echo "FAIL: CharRangeTest.java was modified by the agent (and is not a benign golden overlay)" >&2
        bad_tree=1
      fi
      ;;
    " M "*) # modified tracked file outside the allowed single source file
      echo "FAIL: a tracked file outside CharRange.java was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files are allowed anywhere except inside the main package
      case "$line" in
        "?? src/main/java/org/apache/commons/lang3/"*)
          echo "FAIL: a new file was added inside the main package: $line" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one modification in the range utility source file"
fi
[ "$ok_prov" = 1 ] || reward=0

# ---------- 1. direct reproduction -------------------------------------------
echo "== direct reproduction =="
probe_tampered=0
if [ ! -f /opt/probe.sh.pristine ] || [ ! -f /opt/Probe.java.pristine ]; then
  echo "FAIL: pristine probe copies missing from the image" >&2; probe_tampered=1
fi
cmp -s /app/probe.sh /opt/probe.sh.pristine || { echo "FAIL: /app/probe.sh was modified (compare vs /opt/probe.sh.pristine)" >&2; probe_tampered=1; }
cmp -s /app/Probe.java /opt/Probe.java.pristine || { echo "FAIL: /app/Probe.java was modified (compare vs /opt/Probe.java.pristine)" >&2; probe_tampered=1; }
if [ "$probe_tampered" = 1 ]; then
  echo "FAIL: the reproduction harness was tampered with; a neutered probe cannot stand in for the real checks" >&2
  reward=0
elif /app/probe.sh > /tmp/probe.out 2>&1; then
  echo "ok: /app/probe.sh exits 0 (all containment checks pass)"
else
  echo "FAIL: /app/probe.sh does not exit 0" >&2
  tail -30 /tmp/probe.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  cp "$GOLDEN" "$SRC/src/test/java/org/apache/commons/lang3/CharRangeTest.java"
  run_mvn "golden testContains_Charrange_negatedArgumentTouchingBounds" /tmp/golden.out \
    -Dtest='CharRangeTest#testContains_Charrange_negatedArgumentTouchingBounds' || true
fi

# ---------- 3. the project's own existing test classes ------------------------
echo "== the project's own test classes around the utility =="
run_mvn "CharRange/CharSet/Range test classes" /tmp/own.out \
  -Dtest='CharRangeTest,CharSetTest,RangeTest,IntegerRangeTest,LongRangeTest,DoubleRangeTest' || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  cls=$(find "$case" -maxdepth 1 -name '*Test.java' -printf '%f\n' | head -1)
  cls="${cls%.java}"
  [ -n "$cls" ] || { echo "FAIL: hidden case $name has no *Test.java" >&2; reward=0; continue; }
  out="/tmp/hidden-${name}.out"
  cp "$case"/*Test.java "$SRC/src/test/java/org/apache/commons/lang3/"
  if run_mvn "hidden case $name ($cls)" "$out" -Dtest="$cls"; then
    :
  else
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0