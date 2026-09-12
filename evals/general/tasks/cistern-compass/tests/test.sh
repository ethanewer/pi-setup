#!/bin/bash
# Verifier for cistern-compass: an upstream-clone debugging task on
# junit-team/junit5.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the CSV reader shared by @CsvSource and @CsvFileSource trims unquoted
# columns with String.strip() (Java's Unicode-aware whitespace) instead of the
# ASCII-only String.trim(), so Unicode White_Space above U+0020 (NBSP, thin
# space, ideographic space, ...) is silently stripped from argument values
# while non-whitespace control characters below U+0020 (NUL, ...) are no
# longer trimmed at all. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, only the three junit-jupiter-params
#      main sources may have been changed for the fix plus the overlaid
#      regression-test file, the regression-test file is byte-identical to the
#      upstream regression test extracted at build time into /opt/golden, the
#      buggy production code actually changed, and no other file in the
#      repository differs);
#   1. runs the project's own existing suite slice for this code path (the
#      full CsvArgumentsProviderTests class containing the upstream regression
#      test, and the sibling CsvFileArgumentsProviderTests class) and requires
#      it green;
#   2. runs two authored hidden cases (a Unicode-whitespace/control-character
#      family through @CsvSource and a trimming family through the
#      @CsvFileSource reader path) with inputs the upstream regression test
#      does not use, plus TWO ADDITIONAL hidden cases GENERATED AT VERIFICATION
#      TIME with random-but-contractual inputs (same discriminating families,
#      fresh random draw per run), all of which fail at the parent commit;
#   3. re-checks the tree provenance after the runs (nothing but the agent's
#      changes may remain).
#
# Randomized cases: the agent could read the authored cases and hardcode their
# expected outputs while leaving the bug in place, so the discriminating tests
# are generated fresh (seeded from /dev/urandom unless HP_SEED is set) and the
# expected values are computed by an independent ASCII-only trim() reimplementation.
# Any correct fix (String.trim() semantics) passes every draw; the buggy parent
# fails every draw because each discriminating test guarantees a White_Space
# character above U+0020 or a non-whitespace control below it at a field edge.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=f8513cbd8b867f0c4252d4d9625d77edc45820cb
FIX_SHA=2a52a0643fba15b52fcf13dd553758fcbc1d0458
GOLDEN=/opt/golden/CsvArgumentsProviderTests.java
GOLDEN_SHA256=8966615c03584ab39ea46b6dd875bc286398b281da82fbdaf224f8006e7e9a03
H1_SHA256=27963a9141f1661fa9bc797445152d68c12da0323d71f4521757c6c6cc096c3e
H2_SHA256=0cb80fa5066f8b164654717ffe887f9b8b25435e7fa309e9c54c2fd5a8511fb4
TESTFILE=jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java
RESULTS=$SRC/jupiter-tests/build/test-results/test
GRADLE_TEST=":jupiter-tests:test"
GOLDEN_CLASS="org.junit.jupiter.params.provider.CsvArgumentsProviderTests"
FILESOURCE_CLASS="org.junit.jupiter.params.provider.CsvFileArgumentsProviderTests"
HIDDEN1="org.junit.jupiter.params.provider.CsvSourceWhitespaceSemanticsHiddenTests"
HIDDEN2="org.junit.jupiter.params.provider.CsvFileSourceWhitespaceSemanticsHiddenTests"
PKGDIR=jupiter-tests/src/test/java/org/junit/jupiter/params/provider

fail() { # fail LABEL [DETAIL]
  echo "FAIL: $1" >&2
  [ -n "${2:-}" ] && { echo "$2" | sed 's/^/    /' >&2; }
  reward=0
}

GRADLE_RC=0
run_gradle() { # run_gradle LABEL OUT CLASS...
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

# check_results LABEL [CLS:MIN ...] REQUIRE_GOLDEN
check_results() {
  local label="$1"; shift
  local require_golden="$1"; shift
  python3 - "$RESULTS" "$label" "$require_golden" "$@" <<'PY' || reward=0
import sys, glob, os
import xml.etree.ElementTree as ET

resdir, label, require_golden = sys.argv[1:4]
pairs = sys.argv[4:]
minimum = {}
for p in pairs:
    cls, mn = p.rsplit(":", 1)
    minimum[cls] = int(mn)
require_golden = require_golden == "1"
golden_marker = "trimsSpacesUsingStringTrim"

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
    return [ts for name, ts in suites.items()
            if name == cls or name.startswith(cls + "$")]

ok = True
for cls, min_n in minimum.items():
    matched = suites_for(cls)
    if not matched:
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
    if cls == "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" and require_golden:
        names = [tc.get("name") or "" for ts in matched for tc in ts.iter("testcase")]
        if not any(golden_marker in n for n in names):
            print(f"FAIL[{label}]: the upstream regression test {golden_marker} did not run", file=sys.stderr)
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
allowed = {
    " M " + "junit-jupiter-params/src/main/java/org/junit/jupiter/params/provider/CsvReaderFactory.java",
    " M " + "junit-jupiter-params/src/main/java/org/junit/jupiter/params/provider/CsvSource.java",
    " M " + "junit-jupiter-params/src/main/java/org/junit/jupiter/params/provider/CsvFileSource.java",
    " M " + "jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java",
}
bad = False
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    if line in allowed:
        print("ok: status line:", line[:100]); continue
    print("FAIL-STATUS:", line); bad = True
sys.exit(1 if bad else 0)
'
[ $? -ne 0 ] && fail "working tree differs from the allowed minimal state"

golden_h1=$(sha256sum "$SRC/$TESTFILE" 2>/dev/null | awk '{print $1}')
if [ -f "$GOLDEN" ]; then
  golden_h2=$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')
else
  golden_h2="missing"
fi
if [ "$golden_h1" = "$GOLDEN_SHA256" ]; then
  echo "ok: regression-test file is byte-identical to the upstream regression test"
else
  fail "the regression-test file does not match the pinned upstream regression test (sha256 $golden_h1) -- it must not be edited"
fi
if [ "$golden_h2" = "$GOLDEN_SHA256" ]; then
  echo "ok: /opt/golden copy still matches the pinned upstream regression test"
else
  fail "/opt/golden does not match the pinned upstream regression test (sha256 $golden_h2)"
fi
if git -C "$SRC" diff --quiet -- "junit-jupiter-params/src/main/java/org/junit/jupiter/params/provider/CsvReaderFactory.java" 2>/dev/null; then
  fail "the buggy production code was not changed (no fix implemented)"
else
  echo "ok: production source changed"
fi

# ---------------------------------------------------------------------------
# generate the randomized hidden cases (fresh inputs per run)
# ---------------------------------------------------------------------------
SEED=${HP_SEED:-$(od -An -N8 -tu8 < /dev/urandom | tr -d ' ')}
SUFFIX=$(printf '%x' "$((SEED % 1000000))")
GEN1="CsvSourceRandomChecks_${SUFFIX}Tests"
GEN2="CsvFileSourceRandomChecks_${SUFFIX}Tests"
GEN1F="$SRC/$PKGDIR/$GEN1.java"
GEN2F="$SRC/$PKGDIR/$GEN2.java"
GEN1_CLS="org.junit.jupiter.params.provider.$GEN1"
GEN2_CLS="org.junit.jupiter.params.provider.$GEN2"
python3 - "$SEED" "$GEN1_CLS" "$GEN2_CLS" "$GEN1F" "$GEN2F" <<'PY' || { fail "randomized hidden-case generator failed"; }
import sys, random, re
seed, c1, c2, f1, f2 = sys.argv[1:6]
rng = random.Random(int(seed))

P  = [0x00A0, 0x1680, 0x2009, 0x202F, 0x205F, 0x3000, 0x2028, 0x2029]
DP = [0x1680, 0x2009, 0x202F, 0x205F, 0x3000, 0x2028, 0x2029]  # also stripped by strip()
C  = [0x0001, 0x0002, 0x000E, 0x001B]

def java(s):
    out = []
    for ch in s:
        cp = ord(ch)
        if cp == 0x0A:
            out.append("\\n")
        elif cp == 0x0D:
            out.append("\\r")
        elif cp == 0x09:
            out.append("\\t")
        elif cp == 0x22:
            out.append('\\"')
        elif cp == 0x5C:
            out.append("\\\\")
        elif cp < 0x20 or cp > 0x7E:
            out.append("\\u%04X" % cp)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'

def trim_j(s):
    return re.sub(r'^[\x00-\x20]+|[\x00-\x20]+$', '', s)

def word():
    return "".join(rng.choice("bcdfghjklmnprstvwz") for _ in range(rng.randint(2, 4)))

def edges(fam, n=None):
    return "".join(chr(rng.choice(fam)) for _ in range(n or rng.randint(1, 3)))

def csv_case(cells):
    return ",".join(cells)

# ---- @CsvSource generated class ------------------------------------------
H1_TESTS = []
w = word()
cc0 = edges([rng.choice(DP)]) + w + edges([rng.choice(DP)])
cc1b = edges([rng.choice(DP)]) + word() + edges([rng.choice(DP)])
H1_TESTS.append(("preservesUnicodeWhitespaceAtBothEdges",
                 [cc0, cc1b],
                 [cc0, cc1b]))  # expected == raw (trim() keeps them)

cs = rng.sample(C, 4)
x1 = edges([cs[0]]) + word()
x2 = edges([cs[1]]) + word() + edges([cs[2]])
x3 = edges([cs[3]]) + word()
x4 = word() + edges([cs[1]])
H1_TESTS.append(("trimsNonWhitespaceControlsBelowU0020",
                 [x1, x2],
                 [trim_j(x1), trim_j(x2)]))
H1_TESTS.append(("trimsControlsSecondLine",
                 [x3, x4],
                 [trim_j(x3), trim_j(x4)]))

m1 = edges([rng.choice(DP)]) + " " + edges([rng.choice(C)]) + word() + edges([rng.choice(C)]) + "\t"
m2 = "\t " + edges([rng.choice(C)]) + word() + edges([rng.choice(DP)])
H1_TESTS.append(("mixesAsciiUnicodeAndControls",
                 [m1, m2],
                 [trim_j(m1), trim_j(m2)]))

sep = rng.sample([0x2028, 0x2029], 2)
n1 = edges([sep[0]]) + word() + edges([sep[1]])
n2 = edges([sep[1]]) + word()
H1_TESTS.append(("lineAndParagraphSeparatorsSurvive",
                 [n1, n2],
                 [n1, n2]))  # expected == raw

d1 = edges(P, 2) + word() + edges(C, 1)
d2 = edges(C, 1) + word() + edges(P, 2)
H1_DISABLED = ("trimmingDisabledKeepsEveryEdgeCharacter", [d1, d2], [d1, d2])

q1 = edges([rng.choice(DP)], 1) + word() + edges([rng.choice(C)], 1)
q2 = edges([rng.choice(P)], 1) + word()
H1_TESTS.append(("quotedFieldsAreNeverTrimmed",
                 ["'" + q1 + "'", "'" + q2 + "'"],
                 [q1, q2]))  # quoted -> never trimmed

H1_TESTS.append(H1_DISABLED)  # identity because trimming is DISABLED (builder suffix below)
testmethods = []
for lbl, cells, exp in H1_TESTS:
    line = java(csv_case(cells))
    if lbl == "trimmingDisabledKeepsEveryEdgeCharacter":
        anno = "csvSource().lines(%s).ignoreLeadingAndTrailingWhitespace(false).build()" % line
    else:
        anno = "csvSource().lines(%s).build()" % line
    jexp = ", ".join(java(e) for e in exp)
    testmethods.append("""\t@Test
\tvoid %s() {
\t\tvar annotation = %s;

\t\tvar arguments = provideArguments(annotation);

\t\tassertThat(arguments).containsExactly(array(%s));
\t}
""" % (lbl, anno, jexp))

h1_src = """/*
 * Randomized hidden case for cistern-compass, generated at verification time.
 * NOT an upstream test. Inputs are drawn fresh per run so precomputed
 * answers cannot exist; only an ASCII-only trim() implementation passes.
 */
package org.junit.jupiter.params.provider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.params.provider.MockCsvAnnotationBuilder.csvSource;
import static org.mockito.Mockito.mock;

import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtensionContext;

class %s {
%s
\tprivate Stream<Object[]> provideArguments(CsvSource annotation) {
\t\tvar provider = new CsvArgumentsProvider();
\t\tprovider.accept(annotation);
\t\treturn provider.provideArguments(mock(), mock(ExtensionContext.class)).map(Arguments::get);
\t}

\tprivate static String[] array(String... elements) {
\t\treturn elements;
\t}
}
""" % (c1.split(".")[-1], "\n".join(testmethods))
open(f1, "w").write(h1_src)

# ---- @CsvFileSource generated class ---------------------------------------
fw1 = word()
fc1 = fw1
fc2 = " " + edges([rng.choice(DP)]) + word() + edges([rng.choice(C)]) + " "
fc3 = word() + edges([rng.choice(C)])
fc4 = " " + edges([rng.choice(DP)]) + word()
content = "\n".join([fc1 + "," + fc2, fc3 + "," + fc4]) + "\n"

qw = word()
qin = " " + edges([rng.choice(P)], 1) + qw + edges([rng.choice(C)], 1) + " "
rq = edges([rng.choice(C)], 1) + qw + "\t"
qcontent = '"' + qin + '",' + rq + "\n"

qx = edges([rng.choice(DP)], 1) + qw + " "
rx = edges([rng.choice(C)], 2) + qw
xcontent = '"' + qx + '",' + rx + "\n"

h2_src = """/*
 * Randomized hidden case for cistern-compass, generated at verification time.
 * NOT an upstream test. Same contract through the @CsvFileSource reader.
 */
package org.junit.jupiter.params.provider;

import static java.nio.charset.StandardCharsets.UTF_8;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.params.provider.MockCsvAnnotationBuilder.csvFileSource;
import static org.mockito.Mockito.doCallRealMethod;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Optional;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.params.provider.CsvFileArgumentsProvider.InputStreamProvider;

class %s {

\t@Test
\tvoid trimsFileColumnsWithAsciiOnlySemantics() {
\t\tvar annotation = csvFileSource().resources("hidden-trim.csv").build();

\t\tvar content = %s;

\t\tvar arguments = provideArguments(annotation, content);

\t\tassertThat(arguments).containsExactly(//
\t\t\tarray(%s), //
\t\t\tarray(%s)//
\t\t);
\t}

\t@Test
\tvoid preservesDisabledTrimming() {
\t\tvar annotation = csvFileSource().resources("hidden-trim.csv")
\t\t\t\t.ignoreLeadingAndTrailingWhitespace(false).build();

\t\tvar content = %s;

\t\tvar arguments = provideArguments(annotation, content);

\t\tassertThat(arguments).containsExactly(array(%s));
\t}

\t@Test
\tvoid preservesQuotedFileColumns() {
\t\tvar annotation = csvFileSource().resources("hidden-trim.csv").build();

\t\tvar content = %s;

\t\tvar arguments = provideArguments(annotation, content);

\t\tassertThat(arguments).containsExactly(array(%s));
\t}

\tprivate Stream<Object[]> provideArguments(CsvFileSource annotation, String content) {
\t\treturn provideArguments(new ByteArrayInputStream(content.getBytes(UTF_8)), annotation);
\t}

\tprivate Stream<Object[]> provideArguments(InputStream inputStream, CsvFileSource annotation) {
\t\tvar provider = new CsvFileArgumentsProvider(new InputStreamProvider() {
\t\t\t@Override
\t\t\tpublic InputStream openClasspathResource(Class<?> baseClass, String path) {
\t\t\t\tassertThat(path).isEqualTo(annotation.resources()[0]);
\t\t\t\treturn inputStream;
\t\t\t}

\t\t\t@Override
\t\t\tpublic InputStream openFile(String path) {
\t\t\t\tassertThat(path).isEqualTo(annotation.files()[0]);
\t\t\t\treturn inputStream;
\t\t\t}
\t\t});
\t\tprovider.accept(annotation);
\t\tvar context = mock(ExtensionContext.class);
\t\twhen(context.getTestClass()).thenReturn(Optional.of(%s.class));
\t\tdoCallRealMethod().when(context).getRequiredTestClass();
\t\treturn provider.provideArguments(mock(), context).map(Arguments::get);
\t}

\tprivate static String[] array(String... elements) {
\t\treturn elements;
\t}
}
""" % (c2.split(".")[-1],
       java(content),
       ", ".join(java(x) for x in [trim_j(fc1), trim_j(fc2)]),
       ", ".join(java(x) for x in [trim_j(fc3), trim_j(fc4)]),
       java(qcontent), ", ".join(java(x) for x in [qin, rq]),
       java(xcontent), ", ".join(java(x) for x in [qx, trim_j(rx)]),
       c2.split(".")[-1])
open(f2, "w").write(h2_src)
print("generated", f1, f2, "seed", seed)
PY

# ---------------------------------------------------------------------------
# 1+2. golden regression class + own suite slice + authored + generated hidden
#      cases, one run
#
# Defenses against "score without fixing":
#   * staged authored hidden files must match their pinned hashes (no
#     weakening of /tests/hidden may survive),
#   * the randomized hidden cases above make precomputed answers impossible,
#   * the compiled outputs and result XMLs are removed first so the run is a
#     fresh compile+execute of the delivered sources (no planted bytecode or
#     forged test-result artifacts can survive).
# ---------------------------------------------------------------------------
echo "== golden regression class + own suite slice + hidden cases =="
H1=0; H2=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"*.java; do
    [ -f "$f" ] || continue
    rel="$PKGDIR/$(basename "$f")"
    h=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
    case "$(basename "$f")" in
      CsvSourceWhitespaceSemanticsHiddenTests.java)
        [ "$h" = "$H1_SHA256" ] || { fail "authored hidden case $(basename "$f") was modified (sha256 $h)"; continue; }
        H1=1 ;;
      CsvFileSourceWhitespaceSemanticsHiddenTests.java)
        [ "$h" = "$H2_SHA256" ] || { fail "authored hidden case $(basename "$f") was modified (sha256 $h)"; continue; }
        H2=1 ;;
    esac
    cp "$f" "$SRC/$rel" || { fail "cannot stage hidden case $(basename "$f")"; continue; }
  done
done
[ "$H1" -eq 1 ] && [ "$H2" -eq 1 ] || fail "authored hidden cases did not stage correctly"
[ -f "$GEN1F" ] && [ -f "$GEN2F" ] || fail "randomized hidden cases were not written"

# Fresh compile+execute of the delivered sources: throw away everything an
# agent could have planted in the build outputs of the two modules involved.
rm -rf "$SRC/junit-jupiter-params/build" \
       "$SRC/jupiter-tests/build/test-results" \
       "$SRC/build/test-results"

if run_gradle "golden + own + authored + randomized hidden" /tmp/run-all.out \
    "$GOLDEN_CLASS" "$FILESOURCE_CLASS" "$HIDDEN1" "$HIDDEN2" "$GEN1_CLS" "$GEN2_CLS"; then
  check_results "all" 1 \
    "$GOLDEN_CLASS:37" "$FILESOURCE_CLASS:34" \
    "$HIDDEN1:6" "$HIDDEN2:2" \
    "$GEN1_CLS:7" "$GEN2_CLS:3"
else
  check_results "all" 1 \
    "$GOLDEN_CLASS:0" "$FILESOURCE_CLASS:0" \
    "$HIDDEN1:0" "$HIDDEN2:0" \
    "$GEN1_CLS:0" "$GEN2_CLS:0"
fi

rm -f "$SRC/$PKGDIR/CsvSourceWhitespaceSemanticsHiddenTests.java" \
      "$SRC/$PKGDIR/CsvFileSourceWhitespaceSemanticsHiddenTests.java" \
      "$GEN1F" "$GEN2F"

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
if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone after verification"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0