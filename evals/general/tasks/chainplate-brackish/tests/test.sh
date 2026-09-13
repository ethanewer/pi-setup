#!/bin/bash
# Verifier for chainplate-brackish: proves the agent's fix in the real
# pylint tree at /app/src by (1) asserting provenance (HEAD still the pinned
# parent commit; every tracked file except the single bug-source file is
# byte-identical to it; no stray untracked files), (2) requiring
# /app/summary.md, (3) rerunning the CLI reproduction and asserting the exact
# W0212 line set (only the other.__class__ line may warn), (4) planting the
# project's own regression test for this bug (extracted from the fix commit
# at image build time into /opt/golden) and running it under the project's
# own pytest harness together with the project's existing access/ functional
# tests, and (5) running three authored hidden cases that reach the same
# protected-access code path from inputs the upstream test does not use.
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

PARENT=9242406e364f537f91e99564400944f685f8b079

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the protected-access check in the classes checker, discovered by the
#    agent, not named in the instruction). We compare through git itself so
#    text filters from the repo's .gitattributes (the tree stores some doc
#    fragments with CRLF that checkout materialises as LF) are applied, and
#    we refuse any untracked non-ignored file. An index-flag guard defeats
#    assume-unchanged/skip-worktree tricks, which would otherwise hide a
#    dirty file from git's own diff.
ok=1
if git ls-files -v | awk '$1 ~ /^[a-z]/ || $1 ~ /^S/ {print $2}' | grep -q .; then
    echo "suspicious index flags (assume-unchanged/skip-worktree):" >> "$LOG"
    git ls-files -v | awk '$1 ~ /^[a-z]/ || $1 ~ /^S/ {print $1, $2}' | head -20 >> "$LOG"
    ok=0
fi
while IFS= read -r f; do
    case "$f" in
        "") : ;;
        pylint/checkers/classes/class_checker.py) : ;;
        *) echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0 ;;
    esac
done < <(git diff --name-only HEAD || true)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the environment is what the task pins (editable pylint, astroid
#    4.2.0b4); the reproduction must then show the fixed line set.
python3 - <<'PY' >> "$LOG" 2>&1 || fail "pylint import/version probe failed (see $LOG)"
import astroid, pylint
assert astroid.__version__ == "4.2.0b4", astroid.__version__
print("astroid", astroid.__version__, "pylint", pylint.__version__)
PY

cat > /tmp/verify_repro.py <<'PY'
class Widget:
    _attr = None
    def access_via_self_class(self):
        if self.__class__._attr is None:
            return self.__class__._attr
        return None
    def access_via_other_object_class(self, other):
        return other.__class__._attr
PY
OUT=$(python3 -m pylint /tmp/verify_repro.py --disable=all --enable=protected-access --score=n --msg-template='{line}:{msg_id}' 2>&1)
GOT=$(printf '%s\n' "$OUT" | sed -n 's/^\([0-9][0-9]*\):W0212$/\1/p' | sort -n | tr '\n' ' ' | sed 's/ $//')
if [ "$GOT" != "8" ]; then
    echo "repro W0212 lines ('$GOT') != '8'; full pylint output:" >> "$LOG"
    printf '%s\n' "$OUT" >> "$LOG"
    fail "reproduction still warns on self.__class__ reads (expected W0212 only on line 8, got '$GOT')"
fi
rm -f /tmp/verify_repro.py

# 5) plant the upstream regression test for this bug (golden bytes from
#    /opt/golden, already in the image; never part of this task tree), run
#    the project's OWN pytest harness on it plus the project's existing
#    access/ functional tests, then restore the planted files. On the
#    unfixed tree this pytest selection fails ('Unexpected in testdata:
#    protected-access' on the self.__class__ lines).
cp /opt/golden/access_to_protected_members.py tests/functional/a/access/access_to_protected_members.py || fail "cannot plant golden .py"
cp /opt/golden/access_to_protected_members.txt tests/functional/a/access/access_to_protected_members.txt || fail "cannot plant golden .txt"
if ! timeout 600 python3 -m pytest tests/test_functional.py \
        -k "access_to_protected_members or access_member_before_definition or access_to__name__ or access_attr_before_def_false_positive" \
        -q -p no:cacheprovider > /tmp/verify_pytest.log 2>&1; then
    tail -40 /tmp/verify_pytest.log >&2
    git restore --worktree --source=HEAD -- \
        tests/functional/a/access/access_to_protected_members.py \
        tests/functional/a/access/access_to_protected_members.txt || true
    fail "golden + access/ functional tests did not pass (see /tmp/verify_pytest.log)"
fi
if grep -qE " [0-9]+ failed" /tmp/verify_pytest.log; then
    tail -40 /tmp/verify_pytest.log >&2
    git restore --worktree --source=HEAD -- \
        tests/functional/a/access/access_to_protected_members.py \
        tests/functional/a/access/access_to_protected_members.txt || true
    fail "pytest reported failures (see /tmp/verify_pytest.log)"
fi
grep -E "passed|failed" /tmp/verify_pytest.log | tail -2
grep -qE "passed" /tmp/verify_pytest.log || {
    git restore --worktree --source=HEAD -- \
        tests/functional/a/access/access_to_protected_members.py \
        tests/functional/a/access/access_to_protected_members.txt || true
    fail "no test passed line in pytest output (see /tmp/verify_pytest.log)"
}
git restore --worktree --source=HEAD -- \
    tests/functional/a/access/access_to_protected_members.py \
    tests/functional/a/access/access_to_protected_members.txt || true

# 6) authored hidden cases: other sources reaching the same protected-access
#    code path from inputs the upstream regression test does not use. For
#    each case, pylint must emit W0212 on exactly the lines given in
#    expected.txt (newline-separated; empty file means none).
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"case.py "$work"/case.py || fail "hidden case $name: missing case.py"
    cp "$case"expected.txt "$work"/expected.txt || fail "hidden case $name: missing expected.txt"
    cd "$work" || fail "hidden case $name: cannot cd"
    OUT=$(python3 -m pylint "$work/case.py" --disable=all --enable=protected-access --score=n --msg-template='{line}:{msg_id}' 2>&1)
    GOT=$(printf '%s\n' "$OUT" | sed -n 's/^\([0-9][0-9]*\):W0212$/\1/p' | sort -n | tr '\n' ' ' | sed 's/ $//')
    WANT=$(sort -n "$work/expected.txt" | tr '\n' ' ' | sed 's/ $//')
    if [ "$GOT" != "$WANT" ]; then
        echo "hidden case $name: W0212 lines got '$GOT' want '$WANT'; pylint output:" >> "$LOG"
        printf '%s\n' "$OUT" >> "$LOG"
        fail "hidden case $name: W0212 line set mismatch (see $LOG)"
    fi
    cd /app/src || fail "cannot cd back to /app/src"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected at least 2"

echo "PASS: provenance, /app/summary.md, repro line set, golden + access/ suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0