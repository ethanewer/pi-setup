#!/bin/bash
# Verifier for companion-flint: proves the agent's fix in the real mypy tree
# at /app/src by (1) asserting the verifier's own trust anchors (golden
# regression test, pristine pre-fix tree, toolchain sha256 pins recorded at
# image build time), (2) asserting provenance (HEAD still the pinned parent
# commit; the upstream fix commit is not reachable from this clone; every
# tracked file except the single source file the bug lives in is
# byte-identical to the parent commit; no untracked stray files), (3)
# requiring the deliverables /app/repro.py, /app/repro.sh and
# /app/summary.md, (4) running the agent's own reproduction against the
# repaired tree (must type-check cleanly) and against a pristine pre-fix
# tree baked at /opt/mypy-parent (must fail with the Incompatible-default
# diagnostic - proving the symptom is real and the reproduction targets it),
# (5) executing the agent's /app/repro.sh in both directions, (6) planting
# the upstream project's own regression test (baked into the image at
# /opt/golden, sha256-pinned) into the tree's type-variable data file and
# requiring it to pass, (7) requiring the full existing type-variable data
# sweep (-k check-typevar: 219 existing cases) plus the planted regression
# test and all hidden cases to pass on the repaired tree, and (8) requiring
# three authored hidden cases to pass on the repaired tree AND fail on a
# pristine copy of the pre-fix tree, so passing the upstream test alone is
# insufficient.
#
# The three authored hidden cases are EMBEDDED in this script itself (they
# live in a heredoc past the exit path and are extracted with sed), so a
# writable /tests mount cannot neuter them; the on-disk /tests/hidden files
# must byte-match the embedded copies or the verifier refuses to run.
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

PARENT=4e349a7c0ba553f7b1ba281d35956f4267208f02
FIX=d0b3fb3c89851f10edce10bb425676f400898e00

H1=$(sed -n '/^#HIDDEN1-BEGIN$/,/^#HIDDEN1-END$/p' "$0" | sed '1d;$d')
H2=$(sed -n '/^#HIDDEN2-BEGIN$/,/^#HIDDEN2-END$/p' "$0" | sed '1d;$d')
H3=$(sed -n '/^#HIDDEN3-BEGIN$/,/^#HIDDEN3-END$/p' "$0" | sed '1d;$d')
HIDDEN_NAMES='testTypeVarDefaultThreeTierLeaf testTypeVarDefaultMultipleInheritance testTypeVarDefaultKwOnlyAndSeveral'

export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/tmp/pycache
rm -rf /tmp/pycache && mkdir -p /tmp/pycache
# Any __pycache__ under the tree is either build residue or a planted stub;
# purge it so every import below is forced to compile from the real source.
find /app/src /opt/mypy-parent -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /app/src -name '*.pyc' -delete 2>/dev/null || true

# 0) trust anchors. The verifier executes the tree, the golden test, the
#    pristine pre-fix tree and the toolchain; an adversarial trial could
#    otherwise swap the pinned files for stubs. sha256 pins recorded at image
#    build time detect any substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-subtypes.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix tree or toolchain integrity check failed (substituted file)"
fi

cd /app/src || fail "/app/src is missing"

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in. A CONTENT check, not a git-status check: the actual bytes of
#    every tracked file on disk are hashed against the pinned commit's own
#    blob, so assume-unchanged/skip-worktree tricks cannot hide a dirty file,
#    and any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        mypy/subtypes.py) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
# 2.5) the set of paths in the git index must be EXACTLY the parent tree's
#      path set. The scans above trust the index; an agent could otherwise
#      `git rm --cached` a tampered file and hide it in .git/info/exclude so
#      that neither the tracked-file scan nor the untracked-file scan sees it.
#      The parent side of the comparison comes from the pinned commit's own
#      tree object, so no index edit can change it.
diff <(git ls-tree -r --name-only "$PARENT") <(git ls-files) > /tmp/pathset.diff 2>&1 || {
    echo "index path set differs from the parent tree's file set:" >> "$LOG"
    head -20 /tmp/pathset.diff >> "$LOG"
    fail "git index does not track exactly the parent tree's file set (see $LOG)"
}
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction, its runner, and the
#    change summary. (The scope check above guarantees the data files the
#    verifier is about to extend are byte-identical to the pinned commit.)
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 3.5) the on-disk hidden cases must match the embedded bytes; grading uses
#      the embedded bytes, so a tampered mount changes nothing, but a
#      mismatch betrays substitution and is refused outright.
for f in /tests/hidden/*/*.test; do
    case "$f" in
        /tests/hidden/h1-three-levels/*) want=$(printf '%s\n' "$H1" | sha256sum | awk '{print $1}') ;;
        /tests/hidden/h2-multiple-inheritance/*) want=$(printf '%s\n' "$H2" | sha256sum | awk '{print $1}') ;;
        /tests/hidden/h3-kwonly/*) want=$(printf '%s\n' "$H3" | sha256sum | awk '{print $1}') ;;
        *) fail "unexpected file under /tests/hidden: $f" ;;
    esac
    have=$(sha256sum "$f" | awk '{print $1}')
    [ "$have" = "$want" ] || fail "hidden case file $f does not match the embedded verifier bytes (tampered)"
done

# 4) the agent's reproduction, both directions, through the project's own
#    binary (python3 -m mypy on the tree). This is the authoritative check;
#    step 5 additionally executes the agent's own runner.
if ( cd /opt/mypy-parent && python3 -m mypy --no-incremental --cache-dir=/tmp/vrpc /app/repro.py > /tmp/repro-prefix.out 2>&1 ); then
    echo "agent repro passed against the PRISTINE PRE-FIX tree (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro-prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
grep -q "Incompatible default for parameter" /tmp/repro-prefix.out || {
    echo "agent repro failed on the pre-fix tree for an unexpected reason; output:" >> "$LOG"
    head -20 /tmp/repro-prefix.out >> "$LOG"
    fail "pre-fix repro failure is not the Incompatible-default symptom (see $LOG)"
}
if ( cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/vrpc /app/repro.py > /tmp/repro-fixed.out 2>&1 ); then
    if grep -q "error:" /tmp/repro-fixed.out; then
        echo "agent repro produced diagnostics on the repaired tree; output:" >> "$LOG"
        head -20 /tmp/repro-fixed.out >> "$LOG"
        fail "repaired-tree repro produced diagnostics (see $LOG)"
    fi
    echo "agent repro clean on the repaired tree"
else
    echo "agent repro exited nonzero on the repaired tree; output:" >> "$LOG"
    head -20 /tmp/repro-fixed.out >> "$LOG"
    fail "agent repro still fails on the repaired tree (see $LOG)"
fi

# 5) the agent's runner, executed in THREE directions: the repaired tree via
#    the default MYPY_DIR, plus two throwaway copies at paths the agent cannot
#    pre-know - one copy of the repaired tree, one of the pristine pre-fix
#    tree. A stub that special-cases a known path (e.g. one that keys on
#    /opt/mypy-parent, or one that only passes for the default /app/src)
#    cannot pass all three, so the runner must genuinely execute mypy from
#    whatever tree MYPY_DIR names - exactly the contract. Output-content
#    assertions additionally require mypy's own success/error lines to be
#    printed through.
if ! bash /app/repro.sh > /tmp/reprosh-fixed.out 2>&1; then
    echo "agent repro.sh failed on the repaired tree; output:" >> "$LOG"
    head -10 /tmp/reprosh-fixed.out >> "$LOG"
    fail "agent repro.sh exited nonzero on the repaired tree (see $LOG)"
fi
grep -q "Success:" /tmp/reprosh-fixed.out || {
    echo "agent repro.sh did not print mypy's success line on the repaired tree; output:" >> "$LOG"
    head -10 /tmp/reprosh-fixed.out >> "$LOG"
    fail "agent repro.sh output on the repaired tree is not mypy's (see $LOG)"
}

RF=$(mktemp -d /tmp/rc.XXXXXX)   # opaque copy of the REPAIRED tree
RP=$(mktemp -d /tmp/rc.XXXXXX)   # opaque copy of the PRE-FIX tree (same prefix as RF)
# Both copies use the SAME unknown prefix so a runner that special-cases a
# path can never tell which opaque tree is repaired and which is pre-fix;
# only genuinely running mypy from each tree can.
if ! { cp -a /app/src/. "$RF/" && cp -a /opt/mypy-parent/. "$RP/"; }; then
    echo "verifier internal: cannot prepare opaque tree copies" >> "$LOG"
    fail "verifier internal error preparing opaque tree copies"
fi
if ! MYPY_DIR="$RF" bash /app/repro.sh > /tmp/reprosh-rf.out 2>&1; then
    echo "agent repro.sh failed on an OPAQUE copy of the repaired tree; output:" >> "$LOG"
    head -10 /tmp/reprosh-rf.out >> "$LOG"
    fail "agent repro.sh did not run mypy from an unknown repaired-tree path (see $LOG)"
fi
grep -q "Success:" /tmp/reprosh-rf.out || {
    echo "agent repro.sh output on the opaque repaired copy is not mypy's; output:" >> "$LOG"
    head -10 /tmp/reprosh-rf.out >> "$LOG"
    fail "agent repro.sh output on the opaque repaired copy is not mypy's (see $LOG)"
}
if MYPY_DIR="$RP" bash /app/repro.sh > /tmp/reprosh-rp.out 2>&1; then
    echo "agent repro.sh PASSED against an OPAQUE copy of the PRE-FIX tree (expected failure)" >> "$LOG"
    fail "agent repro.sh did not fail on an unknown pre-fix-tree path (see $LOG)"
fi
grep -q "Incompatible default for parameter" /tmp/reprosh-rp.out || {
    echo "agent repro.sh pre-fix failure lacks the Incompatible-default diagnostic; output:" >> "$LOG"
    head -10 /tmp/reprosh-rp.out >> "$LOG"
    fail "agent repro.sh output on the pre-fix copy is not the bug's diagnostic (see $LOG)"
}
rm -rf "$RF" "$RP"

# 6) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time through a throwaway clone and sha256-pinned;
#    never part of this task tree) into the tree's type-variable data file,
#    then run it individually.
cat /opt/golden/golden-case.test >> test-data/unit/check-typevar-values.test \
    || fail "cannot plant golden case into check-typevar-values.test"
if ! python3 -m pytest mypy/test/testcheck.py -k testTypeVarValuesSubtypeOfAll -n 1 -q > /tmp/golden.out 2>&1; then
    tail -25 /tmp/golden.out >&2
    fail "upstream regression test testTypeVarValuesSubtypeOfAll did not pass (see $LOG)"
fi
grep -q "1 passed" /tmp/golden.out || {
    tail -10 /tmp/golden.out >&2
    fail "upstream regression test did not report 1 passed (see $LOG)"
}

# 7) plant the authored hidden cases into the same data file, then require
#    the full existing type-variable sweep PLUS the golden test PLUS the
#    hidden cases to pass on the repaired tree (219 existing cases + golden +
#    3 hidden = 223).
printf '%s\n' "$H1" "$H2" "$H3" >> test-data/unit/check-typevar-values.test \
    || fail "cannot plant hidden cases into check-typevar-values.test"
if ! python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q > /tmp/sweep.out 2>&1; then
    tail -30 /tmp/sweep.out >&2
    fail "type-variable data sweep did not pass on the repaired tree (see $LOG)"
fi
grep -q "223 passed" /tmp/sweep.out || {
    tail -10 /tmp/sweep.out >&2
    fail "expected 223 passed (219 existing + golden + 3 hidden), see $LOG"
}
for t in $HIDDEN_NAMES; do
    if ! python3 -m pytest mypy/test/testcheck.py -k "$t" -n 1 -q > /tmp/hc-$t.out 2>&1; then
        tail -25 /tmp/hc-$t.out >&2
        fail "hidden case $t did not pass on the repaired tree (see $LOG)"
    fi
    grep -q "1 passed" /tmp/hc-$t.out || fail "hidden case $t did not report 1 passed (see $LOG)"
done

# 8) hidden cases must genuinely exercise the bug: each must FAIL on a
#    pristine copy of the pre-fix tree (planted into a throwaway copy of
#    /opt/mypy-parent). An agent could otherwise satisfy the verifier with a
#    golden test alone, and a hidden case that passes on the buggy tree is
#    not measuring anything.
rm -rf /tmp/parentverify
cp -a /opt/mypy-parent /tmp/parentverify || fail "cannot copy pre-fix tree for the hidden-case negative check"
printf '%s\n' "$H1" "$H2" "$H3" >> /tmp/parentverify/test-data/unit/check-typevar-values.test
neg_ok=1
for t in $HIDDEN_NAMES; do
    if ( cd /tmp/parentverify && python3 -m pytest mypy/test/testcheck.py -k "$t" -n 1 -q > /tmp/pv-$t.out 2>&1 ); then
        echo "hidden case $t PASSED on the pristine pre-fix tree (expected failure)" >> "$LOG"
        neg_ok=0
    fi
done
rm -rf /tmp/parentverify
[ "$neg_ok" = "1" ] || fail "at least one hidden case passed on the pre-fix tree (see $LOG)"

echo "PASS: provenance, fix-unreachable, scope, deliverables, repro both directions (direct + runner), upstream regression test, full typevar sweep, and hidden cases (pass on fixed, fail on pre-fix)"
echo 1 > /logs/verifier/reward.txt
exit 0

# --- embedded hidden-case bytes (dead data, extracted by sed above) ---------
cat <<'CASE1' > /dev/null
#HIDDEN1-BEGIN

[case testTypeVarDefaultThreeTierLeaf]
from typing import TypeVar
class A: ...
class B(A): ...
class C(B): ...
T = TypeVar("T", A, B, C)
c = C()
def f(x: T = c):  # OK: the default is a subtype of every value type
    ...
def g(x: T = B()):  # E: Incompatible default for parameter "x" (default has type "B", parameter has type "T")
    ...
#HIDDEN1-END
CASE1
cat <<'CASE2' > /dev/null
#HIDDEN2-BEGIN

[case testTypeVarDefaultMultipleInheritance]
from typing import TypeVar
class L: ...
class R: ...
class LR(L, R): ...
U = TypeVar("U", L, R)
lr = LR()
def f(x: U = lr):  # OK: a subtype of both value types without being one of them
    ...
def g(x: U = object()):  # E: Incompatible default for parameter "x" (default has type "object", parameter has type "U")
    ...
#HIDDEN2-END
CASE2
cat <<'CASE3' > /dev/null
#HIDDEN3-BEGIN

[case testTypeVarDefaultKwOnlyAndSeveral]
from typing import TypeVar
class P: ...
class Q(P): ...
S = TypeVar("S", P, Q)
q = Q()
def f(x: S = q, *, y: S = q):  # OK: both defaults are of a value type
    ...
def g(x: S = q, *, y: S = P()):  # E: Incompatible default for parameter "y" (default has type "P", parameter has type "S")
    ...
#HIDDEN3-END
CASE3