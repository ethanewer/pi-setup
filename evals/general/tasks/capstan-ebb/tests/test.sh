#!/usr/bin/env bash
# Verifier for capstan-ebb: proves the agent's fix in the real bandit tree at
# /app/src by (1) asserting provenance (HEAD still the pinned parent commit,
# the object store holds nothing beyond it, every tracked file except the one
# SQL-injection plugin file is byte-identical to it, no stray untracked files,
# and the fix commit is unreachable), (2) requiring /app/summary.md, (3)
# proving bandit imports live from /app/src, (4) re-running the issue's exact
# reproduction and demanding one B608 Medium/Medium finding, (5) planting the
# upstream project's own regression test for this bug (fix-version
# examples/sql_statements.py and tests/functional/test_functional.py, extracted
# at image build time into /opt/golden, never vendored into this task tree) and
# running the project's own unittest on the single regression test, on the
# whole functional module and on the whole unit suite, and (6) running three
# authored hidden bandit scans on inputs the upstream regression test never
# uses (lower-case %-formatted executemany, f-string/str.format construction,
# implicit-concat multi-line statement), demanding the VALUES( lines produce
# B608 findings while the parameterised control lines stay clean.
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

# 0) tripwire: prove nothing under /usr or /opt changed since the image was
#    built. The trial can run as root, so without this an agent could plant a
#    sitecustomize.py or .pth, or edit an installed dependency, and make bandit
#    LOOK fixed while /app/src stays byte-identical, defeating every
#    provenance check below. The manifest was hashed by the Dockerfile at the
#    end of the build; this recomputes the same command and must match exactly.
#    (Bytecode caches are excluded: imports legitimately regenerate them.)
TRIP=/var/lib/usr-tripwire.sha256
if [ ! -f "$TRIP" ] || [ ! -s "$TRIP" ]; then
    fail "tripwire manifest missing: environment Dockerfile must generate /var/lib/usr-tripwire.sha256"
fi
{
    find /usr /opt -type f \( -name '*.py' -o -name '*.pth' -o -name '*.so' \) \
        -not -path '*/__pycache__/*' 2>/dev/null | sort
    find /usr/local/bin -maxdepth 1 -type f 2>/dev/null | sort
} | xargs -r sha256sum > /tmp/usr-now.sha256
if ! diff -q "$TRIP" /tmp/usr-now.sha256 >/dev/null 2>&1; then
    diff "$TRIP" /tmp/usr-now.sha256 | head -20 > "$LOG.tripwire-diff"
    echo "files under /usr,/opt,/usr/local/bin differ from build-time tripwire (head of diff):" >> "$LOG"
    head -20 "$LOG.tripwire-diff" >> "$LOG"
    fail "interpreter environment mutated since image build (wrapper/sitecustomize/pth intercept); fix must live in /app/src"
fi
echo "tripwire: /usr,/opt,/usr/local/bin byte-identical to image build" >> "$LOG"

PARENT=b790ce22f0a69f53468c1755e9d37e6349a2c8c2
FIX=3c56109061524f5907cc4d475b7370bac47a451b
GOLDEN_EXAMPLE_SHA=4f0f942b6d774451745e7cfdf978ffa9420e4c075f587f6d6381b1b346ce79f7
GOLDEN_TEST_SHA=c708e836f60d17b91c288e838140f13ca235ac891c92b48bccab9f22e245e009

# 0) deliverables exist
[ -d /app/src/.git ] || fail "/app/src is not a git checkout"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

cd /app/src || fail "cannot cd /app/src"

# 1) the tree must still be at the pinned parent commit (no commits added).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (bandit/plugins/injection_sql.py, discovered by the agent, not named
#    anywhere in the task). CONTENT check: hash the actual bytes of every
#    tracked file against the pinned commit's own blob (assume-unchanged /
#    skip-worktree tricks cannot hide a dirty file), and refuse any untracked
#    non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        bandit/plugins/injection_sql.py) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f (have=$have want=$want)" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) belt: the object store must hold nothing beyond the pinned parent commit:
#    no unreachable objects, and the fix commit must not be reachable at all.
unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see fsck)"
fi
if git cat-file -e ${FIX}^{commit} 2>/dev/null; then
    fail "fix commit ${FIX} is reachable from /app/src's object store"
fi

# 4) deliverable: /app/src must be the live installation, so the agent's edit
#    is what bandit actually imports and what every test runs.
cd /tmp
ED=$(python -c "import bandit; print(bandit.__file__)" 2>/dev/null)
case "$ED" in
    /app/src/*) : ;;
    *) fail "bandit imports from '$ED', not from /app/src (editable install broken)" ;;
esac

# 5) the issue's exact reproduction: after the fix bandit must report exactly
#    one B608 finding (Medium/Medium) at the execute line.
printf '%s\n' \
    'import sqlite3' \
    "conn = sqlite3.connect('app.db')" \
    'cur = conn.cursor()' \
    "value = \"x' OR '1'='1\"" \
    'cur.execute("INSERT INTO foo VALUES(%s)" % value)' \
    > /tmp/values.py
(cd /tmp && bandit -f json /tmp/values.py > /tmp/repro.json 2>/dev/null || true)
python3 -c 'import json, sys

d = json.load(open(sys.argv[1]))
r = [(x["test_id"], x["line_number"], x["issue_severity"], x["issue_confidence"])
     for x in d["results"]]
assert r == [("B608", 5, "MEDIUM", "MEDIUM")], r' /tmp/repro.json 2>/tmp/repro_err.txt
if [ $? -ne 0 ]; then
    echo "repro output: $(cat /tmp/repro_err.txt)" >> "$LOG"
    fail "reproduction did not yield exactly one B608 Medium/Medium at line 5"
fi
echo "repro: exactly one B608 Medium/Medium finding at VALUES( line 5" >> "$LOG"

# 6) golden assets: pinned hashes catch tampering, then plant the upstream
#    regression test (fix-version example + functional test file) into the
#    checked-out tree. The parent-version files are replaced by their
#    successor-revision bytes, which is precisely the state in which the
#    upstream project proves the bug fixed.
GOT=$(sha256sum /opt/golden/sql_statements.py 2>/dev/null | cut -d' ' -f1)
[ "$GOT" = "$GOLDEN_EXAMPLE_SHA" ] || fail "golden example tampered with (sha256 $GOT)"
GOT=$(sha256sum /opt/golden/test_functional.py 2>/dev/null | cut -d' ' -f1)
[ "$GOT" = "$GOLDEN_TEST_SHA" ] || fail "golden functional test tampered with (sha256 $GOT)"
cp /opt/golden/sql_statements.py /app/src/examples/sql_statements.py || fail "cannot plant golden example"
cp /opt/golden/test_functional.py /app/src/tests/functional/test_functional.py || fail "cannot plant golden functional test"

# 7) the project's own unittest: the single regression test by name, then the
#    whole functional module (79 tests across every plugin), then the whole
#    unit suite (178 tests).
cd /app/src || fail "cannot cd /app/src"
echo "=== unittest: single regression test ===" >> "$LOG"
if ! python3 -m unittest tests.functional.test_functional.FunctionalTests.test_sql_statements \
        > /logs/verifier/golden_single.log 2>&1; then
    tail -30 /logs/verifier/golden_single.log >&2
    fail "golden regression test test_sql_statements FAILED (see golden_single.log)"
fi
echo "=== unittest: full functional module ===" >> "$LOG"
if ! python3 -m unittest tests.functional.test_functional \
        > /logs/verifier/functional.log 2>&1; then
    tail -30 /logs/verifier/functional.log >&2
    fail "project functional module FAILED (see functional.log)"
fi
if ! grep -Fq "Ran 79 tests" /logs/verifier/functional.log; then
    fail "functional module did not run its 79 tests (see functional.log)"
fi
echo "=== unittest: full unit suite ===" >> "$LOG"
if ! python3 -m unittest discover -s tests/unit -p 'test_*.py' \
        > /logs/verifier/unit.log 2>&1; then
    tail -30 /logs/verifier/unit.log >&2
    fail "project unit suite FAILED (see unit.log)"
fi
if ! grep -Fq "Ran 178 tests" /logs/verifier/unit.log; then
    fail "unit suite did not run its 178 tests (see unit.log)"
fi

# 8) hidden cases: three authored bandit scans on inputs the upstream
#    regression test never uses. For each, bandit (the project's own binary,
#    running the tree) must report EXACTLY the expected B608 findings and
#    nothing else, so the parameterised control lines are proven clean.
cd /tmp
check_case() {
    local name=$1
    local dir="/tests/hidden/$name"
    local input expected out
    input=$(find "$dir" -maxdepth 1 -name '*.py' | head -1)
    expected="$dir/expected.json"
    [ -n "$input" ] || { echo "hidden $name: no input .py" >> "$LOG"; return 1; }
    [ -f "$expected" ] || { echo "hidden $name: no expected.json" >> "$LOG"; return 1; }
    out="/tmp/hidden_${name}.json"
    bandit -f json "$input" > "$out" 2>/dev/null || true
    python3 -c '
import json, sys
exp_file, got_file, name = sys.argv[1], sys.argv[2], sys.argv[3]
exp = sorted((e["test_id"], e["line_number"], e["issue_severity"], e["issue_confidence"])
             for e in json.load(open(exp_file)))
d = json.load(open(got_file))
got = sorted((r["test_id"], r["line_number"], r["issue_severity"], r["issue_confidence"])
             for r in d["results"])
assert got == exp, "hidden %s expected %s got %s" % (name, exp, got)
print("hidden %s OK: %d B608 finding(s) exactly as expected" % (name, len(exp)))
' "$expected" "$out" "$name" >> "$LOG" 2>&1 || { tail -3 "$LOG" >&2; return 1; }
    return 0
}
for c in executemany fstring-format multiline-insert; do
    if ! check_case "$c"; then
        fail "hidden case $c FAILED (see $LOG)"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0