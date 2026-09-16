#!/bin/bash
# Verifier for capstan-hull: an upstream-clone debugging task on
# apache/commons-lang.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Fraction.multiplyBy throws a spurious ArithmeticException ("overflow:
# mulPos") whenever either operand is not reduced, even when the reduced
# product fits an int. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the only modified tracked
#      source file is Fraction.java with at least one such modification, a
#      FractionTest.java overlay is tolerated only when it is byte-identical
#      to the golden file, and no untracked file appears inside the math
#      package source tree);
#   1. runs the direct reproduction /app/probe.sh (must exit 0);
#   2. requires /app/summary.md to exist and be non-empty;
#   3. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/
#      (the testMultiply and testDivide methods);
#   4. runs the project's own test classes around the utility (FractionTest,
#      FractionReadObjectTest, NumberUtilsTest, IEEE754rUtilsTest), proving
#      the fix broke nothing else;
#   5. runs three authored hidden-case files: products where BOTH operands
#      are unreduced and near the int limit, quotients/powers with
#      unreduced divisors, and guards that a genuinely overflowing product
#      still throws while zero/identity/sign behaviour is unchanged.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=9d1f110190081801754a8a0b447693ad2407a502
FIX_SHA=10f4421456b891d5a426348511383f387c99f3e1
GOLDEN=/opt/golden/FractionTest.java
MVN=/opt/apache-maven-3.9.9/bin/mvn
MFLAGS="-DfailIfNoTests=false -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true -Dmaven.repo.local=/opt/m2repo"

# ---------------------------------------------------------------------------
# Integrity of the shipped fixtures. The agent runs in the same container the
# verifier later uses (as root), so the verifier re-checks that every file it
# relies on is byte-identical to what the image was built with:
#   - /app/probe.sh and /app/FractionProbe.java (the reproduction probe),
#   - /opt/golden/FractionTest.java (the upstream regression test), extracted
#     at image build time from the upstream FIX commit 10f4421..., and
#   - tests/hidden/* (the authored hidden cases), re-uploaded pristine by the
#     harness, then re-checked against these hashes here.
# A root agent could replace any of them; a mismatching byte means the check
# was tampered with and the trial scores 0.
# ---------------------------------------------------------------------------
PROBE_SHA=2192c7155cba75136d5c5a5e3ed4a076cee34cd10711d7c4dad60031e58bca77
PROBE_SRC_SHA=cc4de1d8e5d20a3202d930ac583bc60399569728c75c2163a77b820f5392de26
GOLDEN_SHA=d3b50fc4ae9db5eafdc8d7a8230f7442fe011b50cb3cfd1bc0bd131913777f17
# Format: hidden-dir:expected-class:sha256-of-the-test-file
HIDDEN_SHA_SPEC="case-guards:FractionMultiplyGuardCaseTest:0d268d126d7a852cc6fa714552d37daf7de6dec878ed2dadc65398b0c4767c3b case-unreduced-divide:FractionUnreducedDivideCaseTest:17d3c9efe80260d0aab9943782a85892d9ef0a1be0fba74e8f7dbafc46234594 case-unreduced-multiply:FractionUnreducedMultiplyCaseTest:6bf64c2fd275b976f3e89b69fbb7f952211a29d1b496c8fa177fd11c524b9f1f"

chk_fixture () {  # chk_fixture LABEL PATH SHA
  local label=$1 path=$2 want=$3 got=""
  if [ -f "$path" ]; then
    got=$(sha256sum "$path" | cut -d' ' -f1)
  fi
  if [ "$got" = "$want" ]; then
    echo "ok: $label is byte-identical to the shipped fixture"
  else
    if [ -z "$got" ]; then
      echo "FAIL: $label is missing or unreadable" >&2
    else
      echo "FAIL: $label was modified (sha256 $got != expected $want)" >&2
    fi
    reward=0
  fi
}

# Resolve the hidden-spec dirs against /tests (harness upload) or the directory
# test.sh itself lives in, whichever actually holds them. The cases live under
# tests/hidden/ in the task tree, so they land at /tests/hidden/ at trial time.
resolved_spec=""
for entry in $HIDDEN_SHA_SPEC; do
  dir=${entry%%:*}; rest=${entry#*:}; cls=${rest%%:*}; sha=${rest#*:}
  if [ -d "/tests/hidden/$dir" ]; then base=/tests/hidden
  elif [ -d "$dir" ]; then base=.
  else base=/tests/hidden; fi
  resolved_spec="$resolved_spec $base/$dir:$cls:$sha"
done

run_mvn () {  # run_mvn LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && "$MVN" -B -q test "$@" $MFLAGS > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
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

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M src/main/java/org/apache/commons/lang3/math/Fraction.java")
      saw_mod=1
      ;;
    " M src/test/java/org/apache/commons/lang3/math/FractionTest.java")
      # benign only if it is byte-identical to the golden regression test
      if [ -f "$GOLDEN" ] && cmp -s "$SRC/src/test/java/org/apache/commons/lang3/math/FractionTest.java" "$GOLDEN"; then
        echo "note: FractionTest.java is a benign overlay of the golden regression test"
      else
        echo "FAIL: FractionTest.java was modified by the agent (and is not a benign golden overlay)" >&2
        bad_tree=1
      fi
      ;;
    " M "*) # modified tracked file outside the allowed single source file
      echo "FAIL: a tracked file outside Fraction.java was modified: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files are allowed anywhere except inside the main package
      case "$line" in
        "?? src/main/java/org/apache/commons/lang3/math/"*)
          echo "FAIL: a new file was added inside the main math package: $line" >&2; bad_tree=1 ;;
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
  echo "ok: at least one modification in the fraction source file"
fi
[ "$ok_prov" = 1 ] || reward=0

# ---------- 1. direct reproduction -------------------------------------------
echo "== shipped-fixture integrity =="
chk_fixture "the reproduction probe /app/probe.sh" /app/probe.sh "$PROBE_SHA"
chk_fixture "the probe source /app/FractionProbe.java" /app/FractionProbe.java "$PROBE_SRC_SHA"
chk_fixture "the golden regression test $GOLDEN" "$GOLDEN" "$GOLDEN_SHA"

# ---------- 1. direct reproduction -------------------------------------------
echo "== direct reproduction =="
if /app/probe.sh > /tmp/probe.out 2>&1; then
  echo "ok: /app/probe.sh exits 0 (all fraction checks pass)"
  grep -E "THREW|RESULT" /tmp/probe.out | sed 's/^/    /'
else
  echo "FAIL: /app/probe.sh does not exit 0" >&2
  tail -40 /tmp/probe.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. summary deliverable -------------------------------------------
echo "== summary deliverable =="
if [ -s /app/summary.md ]; then
  echo "ok: /app/summary.md exists and is non-empty"
else
  echo "FAIL: /app/summary.md is missing or empty" >&2
  reward=0
fi

# ---------- 3. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
golden_ok=1
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; golden_ok=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  echo "FAIL: the golden regression test at $GOLDEN was modified (not the upstream fix-commit file)" >&2
  golden_ok=0
fi
if [ "$golden_ok" = 1 ]; then
  cp "$GOLDEN" "$SRC/src/test/java/org/apache/commons/lang3/math/FractionTest.java"
  run_mvn "golden testMultiply+testDivide" /tmp/golden.out \
    -Dtest='FractionTest#testMultiply+testDivide' || true
fi

# ---------- 4. the project's own existing test classes ------------------------
echo "== the project's own test classes around the utility =="
run_mvn "Fraction and math test classes" /tmp/own.out \
  -Dtest='FractionTest,FractionReadObjectTest,NumberUtilsTest,IEEE754rUtilsTest' || true

# ---------- 5. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for entry in $resolved_spec; do
  dir=${entry%%:*}; rest=${entry#*:}; cls=${rest%%:*}; want=${rest#*:}
  case "$dir" in
    /*) case_dir="$dir" ;;
    *)  case_dir="/tests/$dir" ;;
  esac
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case_dir")
  expected_file="$case_dir/$cls.java"
  out="/tmp/hidden-${name}.out"
  if [ ! -d "$case_dir" ]; then
    echo "FAIL: hidden case directory $case_dir is missing" >&2; reward=0; continue
  fi
  extras=$(find "$case_dir" -maxdepth 1 -type f -name '*.java' ! -name "$cls.java" -printf '%f ' 2>/dev/null)
  if [ -n "$extras" ]; then
    echo "FAIL: hidden case $name contains unexpected test files: $extras" >&2; reward=0
  fi
  if [ ! -f "$expected_file" ]; then
    echo "FAIL: hidden case $name lost its test file $expected_file" >&2; reward=0
    continue
  fi
  got=$(sha256sum "$expected_file" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    echo "FAIL: hidden case $name was modified (sha256 $got != expected $want)" >&2
    reward=0
    continue
  fi
  cp "$expected_file" "$SRC/src/test/java/org/apache/commons/lang3/math/"
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