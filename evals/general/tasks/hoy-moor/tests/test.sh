#!/bin/bash
# Verifier for hoy-moor: an upstream-clone debugging task on junit-team/junit5
# (real upstream issue #5098). At the pinned parent commit, a package-private
# test method inherited from a superclass in a DIFFERENT package is silently
# dropped from discovery/execution as soon as a subclass declares a method with
# the same name and parameter list, because method selectors deduplicate on
# class-name + method-name + parameter-type-names without regard to the
# declaring class. The agent must (a) author /app/reproduce.sh, a reproduction
# that fails on the broken tree and passes on the repaired one, then (b) fix
# the production discovery/selector code. The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit, the
#      upstream fix commit not reachable, only production main-source files
#      under the three framework modules modified, no new files, at least one
#      of the seven files the real fix touches actually changed, and the
#      /app/reproduce.sh deliverable present and executable);
#   1. runs the agent's OWN reproduction against a pristine pre-fix copy of
#      the tree (must exit NON-zero: it must genuinely detect the bug);
#   2. runs the agent's own reproduction against /app/src with the fix (must
#      exit zero);
#   3. runs a slice of the tree's own engine suite on the repaired tree
#      (proves the fix broke nothing else);
#   4. swaps in the project's own regression tests for the bug (extracted from
#      the upstream fix commit at image build time into /opt/golden) and runs
#      them together with three authored hidden cases (same discovery path,
#      different inputs), requiring the golden regression tests to be among the
#      executed tests and green;
# then restores every file it touched and re-asserts the provenance snapshot.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

# ---------------------------------------------------------------------------
# 0a. integrity anchors. The verifier's authoritative inputs (the regression
#     tests extracted from the upstream fix commit and the authored hidden
#     cases) are pinned to the exact bytes shipped at authoring time, so an
#     agent that modifies any of them (instead of fixing the bug) fails here.
# ---------------------------------------------------------------------------
GOLDEN_SHA_1=1ea5b15da647f6dfe2728f03b744d095997497da98b77eb4e18430feffccb4db
GOLDEN_SHA_2=4c37328f56fe5b00618fc0e6d44817dcac91bf76ee8964187f4bff5f6cb8a81f
HIDDEN_SHA_1=ea6e384aa370fb557457381da53adb7d2e4c43549dafe1cdbd4dae00cd8df98d
HIDDEN_SHA_2=7bfa6c99ca66aab19cca36c8561aa08106a85809ea604a3d61e961132c5d2660
HIDDEN_SHA_3=b4349429c8242708ac6f50c95836cd2944ee5669614fdcd7b3c28dfdc9c8f915

anchor_ok=1
sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
check_anchor() { # label file expected_sha -> sets anchor_ok=0 on mismatch
  local got; got=$(sha_of "$2")
  if [ "$got" != "$3" ]; then
    echo "FAIL: integrity anchor \"$1\" was modified inside the trial container" >&2
    echo "    sha256 $got != expected $3" >&2
    anchor_ok=0
  else
    echo "ok: integrity anchor $1"
  fi
}
check_anchor golden-main /opt/golden/TestMethodOverridingTests.java "$GOLDEN_SHA_1"
check_anchor golden-sub  /opt/golden/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java "$GOLDEN_SHA_2"
check_anchor hidden/H1 /tests/hidden/case-cross-package-noargs/CrossPackagePackagePrivateNoArgMethodTests.java "$HIDDEN_SHA_1"
check_anchor hidden/H2 /tests/hidden/case-three-level/ThreeLevelPackagePrivateMethodTests.java "$HIDDEN_SHA_2"
check_anchor hidden/H3 /tests/hidden/case-genuine-override/GenuinePublicOverrideRegressionTests.java "$HIDDEN_SHA_3"
[ "$anchor_ok" = 0 ] && reward=0

SRC=/app/src
PARENT_SHA=f5b43ce4e82796d225fe6ecbbfe8a0ad1bed27c4
FIX_SHA=1866c0c21b177f10364aafb17d6b61dd7c80e476
GOLDEN_MAIN=/opt/golden/TestMethodOverridingTests.java
GOLDEN_SUB=/opt/golden/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java
TESTFILE_DIR=jupiter-tests/src/test/java/org/junit/jupiter/engine
SUB_TESTFILE=jupiter-tests/src/test/java/org/junit/jupiter/engine/subpackage/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java
RESULTS=$SRC/jupiter-tests/build/test-results/test
GRADLE_TEST=":jupiter-tests:test"
GOLDEN_TEST="org.junit.jupiter.engine.TestMethodOverridingTests"
HIDDEN_TEST1="org.junit.jupiter.engine.hidden.CrossPackagePackagePrivateNoArgMethodTests"
HIDDEN_TEST2="org.junit.jupiter.engine.hidden.ThreeLevelPackagePrivateMethodTests"
HIDDEN_TEST3="org.junit.jupiter.engine.hidden.GenuinePublicOverrideRegressionTests"
OWN_TESTS=( "org.junit.jupiter.engine.LifecycleMethodOverridingTests"
            "org.junit.jupiter.engine.OverloadedTestMethodTests"
            "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests"
            "org.junit.jupiter.engine.discovery.DiscoveryTests" )
# The seven production files whose change proves the discovery/selector area
# was actually touched (the exact files the upstream fix modifies).
BUG_FILES=(
  "junit-jupiter-engine/src/main/java/org/junit/jupiter/engine/discovery/ClassSelectorResolver.java"
  "junit-jupiter-engine/src/main/java/org/junit/jupiter/engine/discovery/DeclaredMethodSelector.java"
  "junit-jupiter-engine/src/main/java/org/junit/jupiter/engine/discovery/MethodSelectorResolver.java"
  "junit-jupiter-engine/src/main/java/org/junit/jupiter/engine/discovery/MethodSegmentResolver.java"
  "junit-jupiter-engine/src/main/java/org/junit/jupiter/engine/discovery/MethodFinder.java"
  "junit-platform-commons/src/main/java/org/junit/platform/commons/util/ReflectionUtils.java"
  "junit-platform-engine/src/main/java/org/junit/platform/engine/discovery/MethodSelector.java"
)

fail() { # fail LABEL [DETAIL]
  echo "FAIL: $1" >&2
  [ -n "${2:-}" ] && { echo "$2" | sed 's/^/    /' >&2; }
  reward=0
}

GRADLE_RC=0
run_gradle() { # run_gradle LABEL OUT PATTERN...
  local label="$1" out="$2"; shift 2
  local args=() p
  for p in "$@"; do args+=(--tests "$p"); done
  ( cd "$SRC" && ./gradlew "$GRADLE_TEST" -Ptesting.enableJaCoCo=false --offline \
        "${args[@]}" > "$out" 2>&1 )
  GRADLE_RC=$?
  if [ "$GRADLE_RC" -eq 0 ]; then
    echo "ok: gradle $label"
    return 0
  fi
  echo "GRADLE-FAIL: $label (gradle exit $GRADLE_RC)" >&2
  tail -60 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# check_xml LABEL [REQUIRE_GOLDEN] TESTCLASS[:min_tests]...
# Verifies the JUnit XML reports Gradle's test task wrote: each named class ran
# at least its minimum number of tests, with zero failures/errors; when
# REQUIRE_GOLDEN=1 the golden regression test methods must be among the
# executed testcases.
check_xml() {
  local label="$1" req_golden="$2"; shift 2
  local specs=("$@")
  python3 - "$RESULTS" "$label" "$req_golden" "${specs[@]}" <<'PY' || reward=0
import sys, glob, os
import xml.etree.ElementTree as ET

resdir, label, req_golden, *specs = sys.argv[1:]
require_golden = req_golden == "1"
minimum = {}
for spec in specs:
    cls, _, cnt = spec.partition(":")
    minimum[cls] = int(cnt) if cnt else 1

def suites_map():
    out = {}
    # Map by FILE NAME (TEST-<FQCN>.xml, '$'-separated for @Nested), which is
    # always the fully-qualified class name; the suite-name attribute is the
    # display name for nested classes.
    for f in glob.glob(os.path.join(resdir, "TEST-*.xml")):
        base = os.path.basename(f)
        if not base.startswith("TEST-") or not base.endswith(".xml"):
            continue
        fqcn = base[len("TEST-"):-len(".xml")]
        try:
            root = ET.parse(f).getroot()
        except Exception:
            continue
        tax = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
        for ts in tax:
            name = ts.get("name") or ""
            if fqcn not in out:
                out[fqcn] = ts
    return out

suites = suites_map()

def suites_for(cls):
    return [ts for fqcn, ts in sorted(suites.items())
            if fqcn == cls or fqcn.startswith(cls + "$")]

ok = True
for cls, min_tests in minimum.items():
    matched = suites_for(cls)
    if not matched:
        print(f"FAIL[{label}]: no result XML for {cls} (did it run?)", file=sys.stderr)
        ok = False
        continue
    tests = sum(int(ts.get("tests", 0)) for ts in matched)
    failures = sum(int(ts.get("failures", 0)) for ts in matched)
    errors = sum(int(ts.get("errors", 0)) for ts in matched)
    skipped = sum(int(ts.get("skipped", 0)) for ts in matched)
    if failures or errors:
        print(f"FAIL[{label}]: {cls}: {failures} failures + {errors} errors", file=sys.stderr)
        for ts in matched:
            for tc in ts.iter("testcase"):
                if tc.find("failure") is not None or tc.find("error") is not None:
                    print("   failing:", tc.get("name"), file=sys.stderr)
        ok = False
    elif tests < min_tests:
        print(f"FAIL[{label}]: {cls}: only {tests} tests executed (min {min_tests})", file=sys.stderr)
        ok = False
    else:
        print(f"ok[{label}]: {cls}: {tests} tests, {failures} failures, {errors} errors, {skipped} skipped")
    if cls == "org.junit.jupiter.engine.TestMethodOverridingTests" and require_golden:
        names = [tc.get("name") or "" for ts in matched for tc in ts.iter("testcase")]
        for required in ("bothPackagePrivateTestMethodsAreDiscovered", "bothPackagePrivateTestMethodsAreExecuted"):
            if not any(required in n for n in names):
                print(f"FAIL[{label}]: the framework regression test {required} did not run", file=sys.stderr)
                ok = False
sys.exit(0 if ok else 1)
PY
}

# ---------------------------------------------------------------------------
# 0. provenance snapshot (before the verifier touches anything)
# ---------------------------------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
else
  head_sha=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  if [ "$head_sha" = "$PARENT_SHA" ]; then
    echo "ok: HEAD is pinned at the parent commit"
  else
    fail "HEAD is $head_sha, expected $PARENT_SHA"
  fi
  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from the working clone (answer fetched, not implemented)"
  else
    echo "ok: fix commit not present in the object store"
  fi
fi

if [ ! -x /app/reproduce.sh ]; then
  fail "deliverable /app/reproduce.sh is missing or not executable"
else
  echo "ok: /app/reproduce.sh present and executable"
  if grep -qE '/tests|/solution|/opt/golden' /app/reproduce.sh; then
    fail "deliverable /app/reproduce.sh references harness-owned paths"
  else
    echo "ok: /app/reproduce.sh references no harness-owned path"
  fi
fi

PORCELAIN_0=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
echo "$PORCELAIN_0" | python3 -c '
import sys, os
ALLOWED_PREFIXES = (
    "junit-jupiter-engine/src/main/",
    "junit-platform-engine/src/main/",
    "junit-platform-commons/src/main/",
)
bad = False
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    p = line[3:]
    if any(p.startswith(pre) for pre in ALLOWED_PREFIXES):
        print("ok: status line:", line[:110])
    else:
        print("FAIL-MODIFIED:", line); bad = True
sys.exit(1 if bad else 0)
'
[ $? -ne 0 ] && fail "working tree differs from the allowed minimal state"
# A repair must actually touch the discovery/selector area: at least one of the
# seven production files the real fix changes must show up either as a tracked
# diff or as a new file. Untracked files are not in `git diff`, so read porcelain.
if [ -n "$PORCELAIN_0" ]; then
  touched_bug_file=0
  while IFS= read -r pline; do
    [ -z "$pline" ] && continue
    ppath=${pline:3}
    for f in "${BUG_FILES[@]}"; do
      if [ "$ppath" = "$f" ]; then
        touched_bug_file=1
      fi
    done
  done <<EOF
$PORCELAIN_0
EOF
  if [ "$touched_bug_file" = 1 ]; then
    echo "ok: at least one of the bug's own production files changed"
  else
    fail "no production file of the discovery/selector area changed (a no-op is not a fix)"
  fi
else
  fail "no production file changed at all (the bug is untouched)"
fi

# ---------------------------------------------------------------------------
# 1. the agent's own reproduction against the PRISTINE pre-fix tree
# ---------------------------------------------------------------------------
echo "== deliverable reproduction against a pristine pre-fix copy =="
PREFIX=/tmp/prefix-tree
rm -rf "$PREFIX"
if cp -a "$SRC" "$PREFIX" 2>/dev/null \
    && git -C "$PREFIX" reset --hard -q "$PARENT_SHA" 2>/dev/null \
    && git -C "$PREFIX" clean -fdq 2>/dev/null; then
  head_sha=$(git -C "$PREFIX" rev-parse HEAD 2>/dev/null || true)
  if [ "$head_sha" != "$PARENT_SHA" ]; then
    fail "pristine copy is not at the parent commit"
  else
    echo "ok: pristine copy at parent commit ($PARENT_SHA)"
    set +e
    /app/reproduce.sh "$PREFIX" > /tmp/repro-prefix.log 2>&1
    repro_rc=$?
    set -e
    if [ "$repro_rc" -ne 0 ]; then
      echo "ok: deliverable reproduction FAILS on the unmodified tree (exit $repro_rc) — it genuinely detects the bug"
    else
      echo "FAIL: the deliverable reproduction EXITED 0 on the unmodified tree; it does not detect the bug" >&2
      tail -40 /tmp/repro-prefix.log | sed 's/^/    /' >&2
      reward=0
    fi
    rm -rf "$PREFIX"
  fi
else
  fail "could not prepare the pristine pre-fix copy"
fi

# ---------------------------------------------------------------------------
# 2. the agent's own reproduction against the repaired tree
# ---------------------------------------------------------------------------
echo "== deliverable reproduction against the repaired tree =="
set +e
/app/reproduce.sh /app/src > /tmp/repro-fixed.log 2>&1
repro_rc=$?
set -e
if [ "$repro_rc" -eq 0 ]; then
  echo "ok: deliverable reproduction passes on the repaired tree (exit 0)"
else
  echo "FAIL: deliverable reproduction exited $repro_rc on the repaired tree (expected 0)" >&2
  tail -40 /tmp/repro-fixed.log | sed 's/^/    /' >&2
  reward=0
fi

# ---------------------------------------------------------------------------
# 3. the tree's own engine slice on the repaired tree
# ---------------------------------------------------------------------------
echo "== own suite: tree's engine slice =="
if run_gradle "own suite" /tmp/run-own.out "${OWN_TESTS[@]}"; then
  check_xml "own" 0 \
    "org.junit.jupiter.engine.LifecycleMethodOverridingTests:9" \
    "org.junit.jupiter.engine.OverloadedTestMethodTests:2" \
    "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests:49" \
    "org.junit.jupiter.engine.discovery.DiscoveryTests:31"
else
  check_xml "own" 0
fi

# ---------------------------------------------------------------------------
# 4. golden regression tests + hidden cases, in one run
# ---------------------------------------------------------------------------
echo "== golden regression tests + hidden cases =="
if [ ! -s "$GOLDEN_MAIN" ] || [ ! -s "$GOLDEN_SUB" ]; then
  fail "golden tests missing from image"
else
  cp "$GOLDEN_MAIN" "$SRC/$TESTFILE_DIR/TestMethodOverridingTests.java" || fail "cannot stage golden main test"
  cp "$GOLDEN_SUB" "$SRC/$SUB_TESTFILE" || fail "cannot stage golden subpackage test"
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    for f in "$case"*.java; do
      [ -f "$f" ] || continue
      pkg=$(grep -m1 '^package ' "$f" | sed 's/package //; s/;//; s/[[:space:]]//g')
      rel="jupiter-tests/src/test/java/$(echo "$pkg" | tr '.' '/')/$(basename "$f")"
      mkdir -p "$SRC/$(dirname "$rel")" || { fail "cannot mkdir for hidden case $(basename "$f")"; continue; }
      cp "$f" "$SRC/$rel" || { fail "cannot stage hidden case $(basename "$f")"; continue; }
      n_hidden=$((n_hidden + 1))
    done
  done
  [ "$n_hidden" -lt 2 ] && fail "fewer than two hidden cases staged"
  if run_gradle "golden + hidden" /tmp/run-golden.out "$GOLDEN_TEST" "$HIDDEN_TEST1" "$HIDDEN_TEST2" "$HIDDEN_TEST3"; then
    check_xml "golden+hidden" 1 \
      "org.junit.jupiter.engine.TestMethodOverridingTests:2" \
      "org.junit.jupiter.engine.hidden.CrossPackagePackagePrivateNoArgMethodTests:1" \
      "org.junit.jupiter.engine.hidden.ThreeLevelPackagePrivateMethodTests:1" \
      "org.junit.jupiter.engine.hidden.GenuinePublicOverrideRegressionTests:1"
  else
    check_xml "golden+hidden" 1
  fi
  rm -f "$SRC/$TESTFILE_DIR/TestMethodOverridingTests.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/master/NoArgPackagePrivateMasterTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/DuplicateNoArgTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/CrossPackagePackagePrivateNoArgMethodTests.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/top/TopLevelPackagePrivateProbeTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/middle/MiddleLevelPackagePrivateProbeTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/BottomLevelProbeTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/ThreeLevelPackagePrivateMethodTests.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/master/PublicOverrideMasterTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/PublicOverrideChildTestCase.java" \
        "$SRC/jupiter-tests/src/test/java/org/junit/jupiter/engine/hidden/GenuinePublicOverrideRegressionTests.java"
  git -C "$SRC" checkout -- "$SUB_TESTFILE" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 5. final provenance: the tree must be exactly as the agent left it
# ---------------------------------------------------------------------------
echo "== final provenance =="
if [ -d "$SRC/.git" ]; then
  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable after verification"
  fi
  head_sha=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  [ "$head_sha" = "$PARENT_SHA" ] || fail "HEAD moved during verification"
fi
PORCELAIN_1=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ "$PORCELAIN_0" = "$PORCELAIN_1" ]; then
  echo "ok: working tree restored to the delivered state"
else
  fail "working tree differs from the delivered state after verification"
  diff <(printf '%s\n' "$PORCELAIN_0") <(printf '%s\n' "$PORCELAIN_1") | sed 's/^/    /' >&2 || true
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0