#!/bin/bash
# Verifier for swivel-longshore: proves the agent's fix in the real
# networkx/networkx tree at /app/src by (1) asserting the verifier's own
# trust anchors (sha256 pins of the golden regression test file, of the
# crisp pre-fix tree's group.py, and of the core toolchain), (2) asserting
# provenance (HEAD still the pinned parent commit; the upstream fix commit
# object is not present in this clone), (3) asserting scope (every tracked
# file except the single source file the bug lives in is byte-identical to
# the parent commit's blob; no stray untracked files), (4) requiring the
# deliverables /app/repro.py and /app/summary.md, (5) running the agent's
# own reproduction against the pristine pre-fix tree (whose per-build
# random location is read from /opt/prefix-path; must FAIL: the repro must
# detect the bug) and against the repaired tree (must PASS), (6) planting the project's OWN upstream
# regression tests for this defect (the fix-commit test_group.py extracted
# at image build time into /opt/golden, sha256-pinned) over the tree's copy
# and requiring all 26 tests to pass, (7) requiring the project's
# previously-existing group/closeness/betweenness centrality tests to stay
# green on the repaired tree, and (8) running three authored hidden cases
# that compare group betweenness against an independent definition-based
# oracle on graphs the upstream tests do not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Belt for the user-site lockdown that is also declared in the image ENV: the
# verifier must never import an agent-planted sitecustomize.py from ~/.local,
# no matter which user the runner uses. Every python3 below ALSO gets -s.
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=a7d049b4992a1f7e9bd376ce7378d3825d0cfa0e
FIX=73cb92bbaed12828848f2609340442119e7e0fe8

cd /app/src || fail "/app/src is missing"

# The pre-fix tree's location is randomized per build and kept root-only;
# the verifier learns it only here, at runtime, so no trial-visible file
# can be hardcoded/special-cased by a reproduction that knows a literal.
PRE=$(cat /opt/prefix-path 2>/dev/null || true)
if [ -z "$PRE" ] || [ ! -d "$PRE" ] || [ ! -r "$PRE/networkx/algorithms/centrality/group.py" ]; then
    fail "/opt/prefix-path does not resolve to a readable pre-fix tree"
fi

# 0) integrity anchors. The verifier executes the golden test, the pre-fix
#    tree and the interpreter/shell/tools; an adversarial root trial could
#    otherwise tamper with any of them to fake a run. The pins recorded at
#    image build time detect substitution before anything is executed.
for p in /opt/pins/golden.sha256 \
         /opt/pins/prefix-group.py.sha256 \
         /opt/pins/python3.sha256 \
         /opt/pins/bash.sha256 \
         /opt/pins/git.sha256 \
         /opt/pins/cp.sha256 \
         /opt/pins/grep.sha256; do
    if ! sha256sum -c "$p" >/dev/null 2>&1; then
        fail "integrity pin failed: $p (substituted file)"
    fi
done

# 1) provenance: tree still detached at the pinned parent commit (no new
#    commits) and the upstream fix commit must not be reachable from this
#    object store.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in. Git's own content comparison of the whole tree (worktree vs
#    HEAD) must list only that file - git's semantics are authoritative for
#    files git itself materialises (including symlinks whose target bytes
#    git stores with trailing newlines). Belt: for every REGULAR tracked
#    file the on-disk bytes are hashed against the pinned parent blob, so
#    update-index --assume-unchanged / --skip-worktree tricks cannot hide
#    an edit even from git's diff; the index oid of every tracked file must
#    still equal the parent blob; and no untracked non-ignored file may
#    exist. (gitlinks are placeholder dirs never materialised by a shallow
#    checkout; symlink repointing changes the index oid and is caught by
#    the index check.)
ok=1
git update-index --refresh >/dev/null 2>&1 || true
changed=$(git diff --name-only HEAD 2>/dev/null || true)
if [ -n "$changed" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ "$f" != "networkx/algorithms/centrality/group.py" ]; then
            echo "git diff vs HEAD lists out-of-scope file: $f" >> "$LOG"; ok=0
        fi
    done <<< "$changed"
fi
while IFS= read -r -d '' f; do
    case "$f" in
        networkx/algorithms/centrality/group.py) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            case "$mode" in
                100644|100755)
                    # regular files: belt-hash the actual worktree bytes
                    have=$(git hash-object -- "$f" 2>/dev/null || true)
                    if [ -n "$have" ] && [ "$have" != "$want" ]; then
                        echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
                    fi
                    ;;
                *) : ;;  # symlinks/gitlinks: git diff + index-oid checks cover them
            esac
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverables: the agent's failing reproduction and change summary.
[ -x /app/repro.py ] || fail "/app/repro.py is missing or not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
if ! grep -q "group_betweenness_centrality" /app/repro.py; then
    fail "/app/repro.py never mentions the affected function"
fi

# 4) the agent's reproduction, both directions. Against the pristine pre-fix
#    tree (baked at image build at the per-build random path $PRE, sha256
#    pins checked above) it must exit NONZERO and print a GBC= line (proving
#    the symptom is real and the reproduction targets it); against the
#    repaired installed tree it must exit 0 with a GBC= line. A third run
#    re-points NX_PACKAGE_ROOT at a RUNTIME-RANDOM COPY of the repaired
#    tree, so a reproduction that merely discriminates on the env var or on
#    known paths without observing the tree fails: env is set in every run
#    and the paths are unpredictable. Finally the GBC= values of the pre-fix
#    and repaired runs must differ, so hardcoding one constant cannot stand
#    in for a reproduction that observes the tree.
(cd /tmp && NX_PACKAGE_ROOT=$PRE python3 -s /app/repro.py \
    > /tmp/repro_prefix.out 2>&1)
rc=$?
if grep -q "GBC=" /tmp/repro_prefix.out; then
    :
else
    echo "agent repro output against pre-fix tree:" >> "$LOG"
    head -20 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro printed no GBC= line on the pre-fix tree (see $LOG)"
fi
if [ "$rc" -eq 0 ]; then
    echo "agent repro exited 0 against the PRE-FIX tree (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
(cd /tmp && python3 -s /app/repro.py > /tmp/repro_fixed.out 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "agent repro exited $rc against the repaired tree; stdout:" >> "$LOG"
    head -20 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro failed on the repaired tree (see $LOG)"
fi
if ! grep -q "GBC=" /tmp/repro_fixed.out; then
    fail "agent repro printed no GBC= line on the repaired tree"
fi
# tree-sensitivity run: a fresh runtime-random COPY of the repaired tree at
# an unpredictable path, NX_PACKAGE_ROOT set (env is set in every run here,
# so an env-discriminating hardcoding reproduction fails this run).
FIXC=$(mktemp -d /tmp/fixc.XXXXXX) || fail "cannot create temp dir for tree copy"
cp -a /app/src/. "$FIXC"/
(cd /tmp && NX_PACKAGE_ROOT=$FIXC python3 -s /app/repro.py > /tmp/repro_src.out 2>&1)
rc=$?
rm -rf "$FIXC"
if [ "$rc" -ne 0 ]; then
    echo "agent repro exited $rc against a fresh copy of the repaired tree; stdout:" >> "$LOG"
    head -20 /tmp/repro_src.out >> "$LOG"
    fail "agent repro is not tree-sensitive: it fails even against a copy of the repaired tree (see $LOG)"
fi
pref=$(sed -n 's/^GBC=//p' /tmp/repro_prefix.out | tail -1)
fixd=$(sed -n 's/^GBC=//p' /tmp/repro_fixed.out | tail -1)
if [ -z "$pref" ] || [ -z "$fixd" ]; then
    fail "agent repro GBC= values unparseable (prefix='$pref' fixed='$fixd')"
fi
python3 -s - "$pref" "$fixd" <<'PY'
import sys
try:
    a, b = float(sys.argv[1]), float(sys.argv[2])
except ValueError:
    sys.exit(1)
# a reproduction that observed the trees must see different values; a
# hardcoded constant would print the same value on both.
if abs(a - b) <= 1e-9:
    sys.exit(1)
sys.exit(0)
PY
if [ "$?" -ne 0 ]; then
    fail "agent repro GBC values do not differ between the pre-fix and repaired trees (hardcoded?)"
fi

# 5) plant the project's OWN upstream regression tests for this defect (the
#    whole fix-commit test_group.py, sha256-pinned and root-only in the image;
#    never part of this task tree) over the tree's copy, run the entire file:
#    all 26 tests must pass, including the two upstream regression tests for
#    this defect.
cp /app/src/networkx/algorithms/centrality/tests/test_group.py /tmp/pristine_test_group.py \
    || fail "cannot snapshot the tree's test_group.py"
cp /opt/golden/test_group.py /app/src/networkx/algorithms/centrality/tests/test_group.py \
    || fail "cannot plant golden test_group.py"
(cd /app/src && python3 -s -m pytest networkx/algorithms/centrality/tests/test_group.py \
    -p no:cacheprovider -v > "$LOG.golden" 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
    tail -30 "$LOG.golden" >&2
    fail "golden test_group.py (with upstream regression tests) did not pass (see $LOG.golden)"
fi
grep -q "26 passed" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "expected 26 passed in the golden run, got a different split (see $LOG.golden)"
}
grep -q "test_group_betweenness_no_paths_through_group" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the upstream no-paths-through-group regression test did not run (see $LOG.golden)"
}
grep -q "test_group_betweenness_many_groups" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the upstream many-groups regression test did not run (see $LOG.golden)"
}

# 6) previously-existing project centrality suites must stay green on the
#    repaired tree (the scope check guarantees their bytes are the pinned
#    commit's; a green run proves the fix broke nothing else). The tree's
#    own test_group.py is restored first.
cp /tmp/pristine_test_group.py /app/src/networkx/algorithms/centrality/tests/test_group.py \
    || fail "cannot restore the tree's test_group.py"
for t in test_group.py test_betweenness_centrality.py test_closeness_centrality.py; do
    (cd /app/src && python3 -s -m pytest "networkx/algorithms/centrality/tests/$t" \
        -p no:cacheprovider -q > "$LOG.$t" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        tail -30 "$LOG.$t" >&2
        fail "existing suite $t failed on the repaired tree (see $LOG.$t)"
    fi
    grep -qE "[0-9]+ passed" "$LOG.$t" || {
        tail -10 "$LOG.$t" >&2
        fail "existing suite $t did not report a passing run (see $LOG.$t)"
    }
done

# 7) three authored hidden cases: group betweenness checked against an
#    independent definition-based oracle on graphs the upstream tests do
#    not use, covering a zero-valued case the buggy code got wrong, a
#    fractional case, and an integer case.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stdout:" >> "$LOG"
        head -15 "$work/stdout.txt" >> "$LOG"
        echo "stderr:" >> "$LOG"
        head -15 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected at least 3"

echo "PASS: provenance, fix-unreachable, scope, deliverables, repro both directions, upstream regression tests, existing centrality suites, hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0