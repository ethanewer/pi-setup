#!/bin/bash
# Verifier for yawl-offing: an upstream-clone debugging task on
# sqlalchemy/sqlalchemy. The agent must fix, in the real checkout at /app/src,
# a real upstream bug: ORM UPDATE/DELETE that uses .returning() whose column
# order differs from the table-declared order, executed with
# execution_options={"synchronize_session": "fetch"}, returns mislabeled
# columns on the second (compiled-cache-hit) execution of the same statement
# shape. The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit; the
#      upstream fix commit is not reachable from the working clone; exactly
#      one commit object exists; the only modified tracked file is the single
#      source file the defect lives in, with at least one modification
#      present - a content check against the parent blobs, not just git status;
#      no deletions, no additions, no leftover untracked files; `import
#      sqlalchemy` resolves to /app/src/lib/sqlalchemy; and a class-scoped
#      source check proving the fix lives in the source tree, not in a
#      runtime wrapper);
#   1. requires the deliverables /app/repro.py (the agent's own failing
#      reproduction, per the instruction's contract) and /app/summary.md;
#   2. runs /app/repro.py against the repaired tree (must exit 0) and,
#      with PYTHONPATH=/opt/pristine-lib (a pristine pre-fix copy baked into
#      the image), against the pre-fix tree (must exit non-zero - proving the
#      symptom is real and the reproduction targets it);
#   3. plants the project's own upstream regression test for this bug
#      (CacheAdaptReturningOrderTest, extracted from the fix commit into
#      /opt/golden at image build time and sha256-pinned) and runs the whole
#      test_orm_upd_del_assorted.py file, including that class explicitly;
#   4. runs the project's own existing test/orm/dml suite;
#   5. runs three authored hidden cases exercising the same code path from
#      inputs the upstream test does not use (4-column scrambled-order
#      multi-column UPDATE; DELETE through three consecutive cache hits with a
#      row-count check; UPDATE returning only a subset of columns with a
#      two-row id.in_() where clause).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT=16177b8c73e492e5adaad8f51095f9981831da41
FIX=bd0da4263052b4571f3b16eda3552e134b9b1689
GOLDEN=/opt/golden/test_orm_upd_del_assorted.py
GOLDEN_SHA=c6318f9a6154963a4f0f8c547779ef71983a040e0f7946522c21e4ad72c1e1bf
PRISTINE_BP_SHA=cb5bd0704a90b7c798a9598fdb9b0e13aa4a792014e16001901f8309403ab02d
LOG=/logs/verifier/verifier.log
: > "$LOG"

export PYTHONDONTWRITEBYTECODE=1

echo "== tree provenance =="

if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT" ]; then
    echo "ok: HEAD is $PARENT"
else
    echo "FAIL: /app/src HEAD is not the pinned parent commit (or not a git clone)" >> "$LOG"
    reward=0
fi

if git -C "$SRC" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >> "$LOG"
    reward=0
else
    echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
    echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit" >> "$LOG"
    reward=0
else
    echo "ok: exactly one commit object reachable in the working clone"
fi

# Scope check: porcelain classification plus a blob-level content comparison
# against the parent commit for every tracked file.
saw_mod=0
bad_tree=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    x=${line:0:1}; y=${line:1:1}; path=${line:3}
    case "$x$y" in
        \?\?)
            case "$path" in
                .pytest_cache/*|__pycache__/*|*.pyc)
                    echo "note: untracked artifact $path (ignored)" ;;
                *conftest.py)
                    echo "FAIL: untracked conftest.py inside the clone (runtime-interception wrapper): $path" >> "$LOG"; bad_tree=1 ;;
                *)
                    echo "FAIL: untracked file inside the clone: $path" >> "$LOG"; bad_tree=1 ;;
            esac
            ;;
        *D*)
            echo "FAIL: a tracked file was deleted: $path" >> "$LOG"; bad_tree=1
            ;;
        A*)
            echo "FAIL: a new tracked file was added: $path" >> "$LOG"; bad_tree=1
            ;;
        *M*)
            case "$path" in
                lib/sqlalchemy/orm/bulk_persistence.py) saw_mod=1 ;;
                *)
                    echo "FAIL: a tracked file outside the bug's source file was modified: $path" >> "$LOG"
                    bad_tree=1 ;;
            esac
            ;;
        *)
            echo "FAIL: unexpected working-tree change: $line" >> "$LOG"; bad_tree=1 ;;
    esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
    echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >> "$LOG"
    reward=0
else
    echo "ok: at least one modification present in the bug's source file"
fi

# content-level check (defeats assume-unchanged / skip-worktree tricks)
while IFS= read -r -d '' f; do
    [ "$f" = "lib/sqlalchemy/orm/bulk_persistence.py" ] && continue
    want=$(git -C "$SRC" rev-parse "$PARENT:$f" 2>/dev/null || true)
    if [ -z "$want" ]; then
        echo "FAIL: tracked file has no parent blob: $f" >> "$LOG"; reward=0; continue
    fi
    have=$(git -C "$SRC" hash-object -- "$SRC/$f" 2>/dev/null || true)
    if [ "$have" != "$want" ]; then
        echo "FAIL: tracked file bytes differ from the pinned commit: $f" >> "$LOG"
        reward=0
    fi
done < <(git -C "$SRC" ls-files -z 2>/dev/null || true)

if ! ( cd / && python3 -c "import sqlalchemy,sys; sys.exit(0 if sqlalchemy.__file__.startswith('$SRC/lib/') else 3)" >/dev/null 2>&1 ); then
    echo "FAIL: 'import sqlalchemy' does not resolve to the checked-out tree at /app/src" >> "$LOG"
    reward=0
else
    echo "ok: import sqlalchemy resolves to $SRC/lib/sqlalchemy"
fi

# The fix must live in the source tree itself: the ORM bulk UPDATE/DELETE
# compile state must merge the ORM load execution options into the effective
# execution options (the same merge the project's own INSERT path already
# performs). A runtime wrapper (sitecustomize.py, a root conftest.py, a
# site-packages shadow) that patches behaviour from outside the clone cannot
# satisfy this, because the checked-out bulk_persistence.py would still lack
# the merge inside the _BulkUDCompileState class.
shape=$(python3 - "$SRC/lib/sqlalchemy/orm/bulk_persistence.py" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'^class _BulkUDCompileState\b.*?(?=^class |\Z)', src, re.S | re.M)
if not m:
    print("NOCLASS")
elif '_orm_load_exec_options' in m.group(0):
    print("OK")
else:
    print("NOFIX")
PY
)
case "$shape" in
    OK) echo "ok: source of _BulkUDCompileState merges the ORM load execution options" ;;
    *) echo "FAIL: the working tree's bulk_persistence.py does not contain the fix (shape check: $shape); the defect must be fixed in the source tree, not in a wrapper" >> "$LOG"; reward=0 ;;
esac

echo "== deliverables =="
if [ ! -x /app/repro.py ]; then
    echo "FAIL: /app/repro.py is missing or not executable" >> "$LOG"; reward=0
else
    echo "ok: /app/repro.py present and executable"
fi
if [ ! -s /app/summary.md ]; then
    echo "FAIL: /app/summary.md is missing or empty" >> "$LOG"; reward=0
else
    echo "ok: /app/summary.md present"
fi

echo "== reproduction, both directions =="
if [ -x /app/repro.py ]; then
    if ( cd / && python3 /app/repro.py > /tmp/repro_fixed.out 2>&1 ); then
        echo "ok: /app/repro.py passes on the repaired tree"
    else
        echo "FAIL: /app/repro.py exited non-zero on the repaired tree; output:" >> "$LOG"
        head -15 /tmp/repro_fixed.out >> "$LOG"
        reward=0
    fi
    # pre-fix direction: prove the pristine copy is really the pristine
    # pre-fix package, then require the reproduction to FAIL on it.
    if ! ( cd / && PYTHONPATH=/opt/pristine-lib python3 -c "import sqlalchemy,sys; sys.exit(0 if sqlalchemy.__file__.startswith('/opt/pristine-lib') else 3)" >/dev/null 2>&1 ); then
        echo "FAIL: PYTHONPATH=/opt/pristine-lib does not resolve to the pristine pre-fix copy" >> "$LOG"
        reward=0
    elif ! test "$(sha256sum /opt/pristine-lib/sqlalchemy/orm/bulk_persistence.py 2>/dev/null | cut -d' ' -f1)" = "$PRISTINE_BP_SHA"; then
        echo "FAIL: the pristine pre-fix copy at /opt/pristine-lib was tampered with (bulk_persistence.py sha256 mismatch)" >> "$LOG"
        reward=0
    elif ( cd / && PYTHONPATH=/opt/pristine-lib python3 /app/repro.py > /tmp/repro_pristine.out 2>&1 ); then
        echo "FAIL: /app/repro.py PASSED against the pristine pre-fix tree (expected failure); output:" >> "$LOG"
        head -15 /tmp/repro_pristine.out >> "$LOG"
        reward=0
    else
        echo "ok: /app/repro.py fails on the pristine pre-fix tree (symptom real)"
    fi
fi

echo "== existing suite: the project's own test/orm/dml =="
if ( cd /app/src && python3 -m pytest test/orm/dml -q -p no:cacheprovider > /tmp/dml_own.out 2>&1 ); then
    tail -1 /tmp/dml_own.out
    echo "ok: test/orm/dml passes on the agent's tree"
else
    tail -30 /tmp/dml_own.out | sed 's/^/    /'
    echo "FAIL: test/orm/dml failed on the agent's tree" >> "$LOG"
    reward=0
fi

echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$case")
    out="/tmp/hidden-${name}.out"
    if ( cd /app/src && python3 -m pytest "$case" -q -p no:cacheprovider --confcutdir=/tests > "$out" 2>&1 ); then
        echo "ok: hidden case $name"
    else
        tail -25 "$out" | sed 's/^/    /'
        echo "FAIL: hidden case $name" >> "$LOG"
        reward=0
    fi
done
if [ "$n_hidden" -lt 3 ]; then
    echo "FAIL: only $n_hidden hidden case(s) ran; expected at least 3" >> "$LOG"
    reward=0
fi

echo "== golden: the project's own upstream regression test for this bug =="
if [ ! -s "$GOLDEN" ]; then
    echo "FAIL: golden test missing from image" >> "$LOG"; reward=0
elif [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
    echo "FAIL: /opt/golden/test_orm_upd_del_assorted.py was tampered with (sha256 mismatch)" >> "$LOG"
    reward=0
else
    echo "ok: golden test integrity confirmed"
    cp "$GOLDEN" /app/src/test/orm/dml/test_orm_upd_del_assorted.py
    if ( cd /app/src && python3 -m pytest test/orm/dml/test_orm_upd_del_assorted.py -q -p no:cacheprovider > /tmp/golden_file.out 2>&1 ); then
        tail -1 /tmp/golden_file.out
        echo "ok: whole test_orm_upd_del_assorted.py (with the planted regression test) passes"
    else
        tail -25 /tmp/golden_file.out | sed 's/^/    /'
        echo "FAIL: test_orm_upd_del_assorted.py with the planted regression test did not pass" >> "$LOG"
        reward=0
    fi
    if ( cd /app/src && python3 -m pytest \
          "test/orm/dml/test_orm_upd_del_assorted.py::CacheAdaptReturningOrderTest" \
          -q -p no:cacheprovider > /tmp/golden_class.out 2>&1 ); then
        grep -q "2 passed" /tmp/golden_class.out && echo "ok: upstream regression class CacheAdaptReturningOrderTest passes 2/2" \
            || { echo "FAIL: regression class did not pass 2/2" >> "$LOG"; reward=0; }
    else
        tail -25 /tmp/golden_class.out | sed 's/^/    /'
        echo "FAIL: upstream regression class CacheAdaptReturningOrderTest failed" >> "$LOG"
        reward=0
    fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0