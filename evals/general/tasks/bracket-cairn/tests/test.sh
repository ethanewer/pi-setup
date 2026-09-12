#!/bin/bash
# Verifier for bracket-cairn: an upstream-clone debugging task on junit-team/junit5.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# nested classes declared in the same enclosing class or interface are returned
# by findNestedClasses/streamNestedClasses in raw JVM reflection order (which
# the JVM API leaves unspecified and thus differs across JDK versions) instead
# of the deterministic order the library already applies to methods and fields
# (fully-qualified name String.hashCode(), lexicographic tie-break). The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, only the minimal production source
#      file(s) modified, no new files under the commons/platform-tests source
#      trees, and the buggy production code actually changed);
#   1. runs the tree's own ReflectionUtilsTests + ReflectionSupportTests
#      (proves the fix did not break the existing suite);
#   2. swaps in the project's own regression test for the bug (extracted from
#      the upstream fix commit at image build time into /opt/golden), runs the
#      whole ReflectionUtilsTests class again and requires the regression test
#      to be among the executed tests and green;
#   3. copies the two authored hidden cases into the tree and runs them (they
#      exercise the same code paths from inputs the upstream test does not use:
#      different class-name inputs, predicate filtering, an inheritance chain,
#      interfaces declaring nested classes, the stream API and the
#      ReflectionSupport facade);
# then restores every file it touched and re-asserts the provenance snapshot.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

# ---------------------------------------------------------------------------
# 0a. integrity anchors. The verifier's authoritative inputs (the regression
#     test extracted from the upstream fix commit and the authored hidden
#     cases) are pinned to the exact bytes shipped at authoring time. The
#     trial runs as root in a long-lived container where /opt/golden is
#     always visible, so an agent that modifies any of these inputs (instead
#     of fixing the bug) must fail here, not score points.
# ---------------------------------------------------------------------------
GOLDEN_SHA=50eb272f3c078b4a148ab7331e9e7c694ab20ea3814aa86a27224952a5f6045c
HIDDEN_SHA_1=210744b5024087c25ec28e0dee6705cd8b3a639b656aff59a7c7286c61b24360
HIDDEN_SHA_2=cf7598d12c817426b75af3a87d017f6ecdab9b012ae96cf239380ad0fd8aa486

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
check_anchor golden /opt/golden/ReflectionUtilsTests.java "$GOLDEN_SHA"
check_anchor hidden/nested /tests/hidden/case-nested-order/NestedClassOrderDeterminismTests.java "$HIDDEN_SHA_1"
check_anchor hidden/stream /tests/hidden/case-stream-order/NestedClassStreamOrderTests.java "$HIDDEN_SHA_2"
[ "$anchor_ok" = 0 ] && reward=0

SRC=/app/src
PARENT_SHA=8307cd49221d90413c66918c7b094274078a6809
FIX_SHA=cb577cf95050cd7b2f64090261fe5a48acb326bc
GOLDEN=/opt/golden/ReflectionUtilsTests.java
TESTFILE=platform-tests/src/test/java/org/junit/platform/commons/util/ReflectionUtilsTests.java
UTILS=junit-platform-commons/src/main/java/org/junit/platform/commons/util/ReflectionUtils.java
SUPPORT=junit-platform-commons/src/main/java/org/junit/platform/commons/support/ReflectionSupport.java
RESULTS=$SRC/platform-tests/build/test-results/test
GRADLE_TEST=":platform-tests:test"
UTILS_TEST="org.junit.platform.commons.util.ReflectionUtilsTests"
SUPPORT_TEST="org.junit.platform.commons.support.ReflectionSupportTests"
HIDDEN_TEST1="org.junit.platform.commons.util.NestedClassOrderDeterminismTests"
HIDDEN_TEST2="org.junit.platform.commons.support.NestedClassStreamOrderTests"

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

# check_results LABEL MIN_UTILS MIN_SUPPORT MIN_H1 MIN_H2 REQUIRE_GOLDEN_NAME(0|1)
# Checks the JUnit XML reports Gradle's test task wrote for the classes we ran.
check_results() {
  local label="$1" min_utils="$2" min_support="$3" min_h1="$4" min_h2="$5" req_golden="$6"
  python3 - "$RESULTS" "$min_utils" "$min_support" "$min_h1" "$min_h2" "$req_golden" "$label" <<'PY' || reward=0
import sys, glob, os
import xml.etree.ElementTree as ET

resdir, min_utils, min_support, min_h1, min_h2, req_golden, label = sys.argv[1:8]
minimum = {
    "org.junit.platform.commons.util.ReflectionUtilsTests": int(min_utils),
    "org.junit.platform.commons.support.ReflectionSupportTests": int(min_support),
    "org.junit.platform.commons.util.NestedClassOrderDeterminismTests": int(min_h1),
    "org.junit.platform.commons.support.NestedClassStreamOrderTests": int(min_h2),
}
require_golden = req_golden == "1"

def suites_map():
    out = {}
    for f in glob.glob(os.path.join(resdir, "TEST-*.xml")):
        try:
            root = ET.parse(f).getroot()
        except Exception:
            continue
        tax = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
        for ts in tax:
            name = ts.get("name") or ""
            if name not in out:
                out[name] = ts
    return out

suites = suites_map()

def suites_for(cls):
    # Gradle writes one XML per @Nested test class; a class filter also runs
    # its nested classes, so collect every suite of the requested class and its
    # nested-class hierarchy.
    return [ts for name, ts in suites.items()
            if name == cls or name.startswith(cls + "$")]

ok = True
for cls, min_n in minimum.items():
    if min_n <= 0:
        continue
    matched = suites_for(cls)
    if not matched:
        # fall back to simple-name suffix only when prefix matching found nothing
        matched = [ts for name, ts in suites.items()
                   if name.endswith("." + cls.split(".")[-1])]
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
    elif tests < min_n:
        print(f"FAIL[{label}]: {cls}: only {tests} tests executed (min {min_n})", file=sys.stderr)
        ok = False
    else:
        print(f"ok[{label}]: {cls}: {tests} tests, {failures} failures, {errors} errors, {skipped} skipped")
    if cls == "org.junit.platform.commons.util.ReflectionUtilsTests" and require_golden:
        names = [tc.get("name") or "" for ts in matched for tc in ts.iter("testcase")]
        if not any("findNestedClassesWithMultipleNestedClasses" in n for n in names):
            print(f"FAIL[{label}]: the framework regression test findNestedClassesWithMultipleNestedClasses did not run", file=sys.stderr)
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

PORCELAIN_0=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
echo "$PORCELAIN_0" | python3 -c '
import sys
allowed = {" M " + sys.argv[1], " M " + sys.argv[2]}
bad = False
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    if line in allowed:
        print("ok: status line:", line[:100]); continue
    if line.startswith("?? "):
        rest = line[3:]
        if rest.startswith("junit-platform-commons/") or rest.startswith("platform-tests/"):
            print("FAIL-NEWFILE:", line); bad = True; continue
        print("ok: untracked outside source trees:", line[:100]); continue
    print("FAIL-MODIFIED:", line); bad = True
sys.exit(1 if bad else 0)
' "$UTILS" "$SUPPORT"
[ $? -ne 0 ] && fail "working tree differs from the allowed minimal state"
if git -C "$SRC" diff --quiet -- "$UTILS" 2>/dev/null; then
  fail "the buggy production code was not changed (no fix implemented)"
else
  echo "ok: production source changed"
fi
# A trivial edit must not count as a fix: the unsorted getDeclaredClasses()
# loop that returns nested classes in raw JVM reflection order must be gone.
if grep -q 'for (Class<?> nestedClass : clazz.getDeclaredClasses())' "$SRC/$UTILS"; then
  fail "the unsorted getDeclaredClasses() loop is still present (bug not fixed)"
else
  echo "ok: unsorted nested-class loop removed from ReflectionUtils.java"
fi

# ---------------------------------------------------------------------------
# 1. own existing suite (as delivered, before touching anything)
# ---------------------------------------------------------------------------
echo "== own suite: tree ReflectionUtilsTests + ReflectionSupportTests =="
if run_gradle "own suite" /tmp/run-own.out "$UTILS_TEST" "$SUPPORT_TEST"; then
  check_results "own" 100 30 0 0 0
else
  check_results "own" 0 0 0 0 0
fi

cp "$SRC/$TESTFILE" /tmp/testfile.pristine || fail "cannot read $TESTFILE"

# ---------------------------------------------------------------------------
# 2. golden regression test + hidden cases, in one run
# ---------------------------------------------------------------------------
echo "== golden regression test + hidden cases =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden test missing from image"
else
  cp "$GOLDEN" "$SRC/$TESTFILE" || fail "cannot stage golden test"
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    for f in "$case"*.java; do
      [ -f "$f" ] || continue
      pkg=$(grep -m1 '^package ' "$f" | sed 's/package //; s/;//; s/[[:space:]]//g')
      rel="platform-tests/src/test/java/$(echo "$pkg" | tr '.' '/')/$(basename "$f")"
      cp "$f" "$SRC/$rel" || { fail "cannot stage hidden case $(basename "$f")"; continue; }
      n_hidden=$((n_hidden + 1))
    done
  done
  [ "$n_hidden" -lt 2 ] && fail "fewer than two hidden cases staged"
  if run_gradle "golden + hidden" /tmp/run-golden.out "$UTILS_TEST" "$HIDDEN_TEST1" "$HIDDEN_TEST2"; then
    check_results "golden+hidden" 100 0 5 2 1
  else
    check_results "golden+hidden" 0 0 0 0 1
  fi
  rm -f "$SRC/platform-tests/src/test/java/org/junit/platform/commons/util/NestedClassOrderDeterminismTests.java" \
        "$SRC/platform-tests/src/test/java/org/junit/platform/commons/support/NestedClassStreamOrderTests.java"
  cp /tmp/testfile.pristine "$SRC/$TESTFILE" 2>/dev/null || true
  rm -f /tmp/testfile.pristine
fi

# ---------------------------------------------------------------------------
# 3. final provenance: the tree must be exactly as the agent left it
# ---------------------------------------------------------------------------
echo "== final provenance =="
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