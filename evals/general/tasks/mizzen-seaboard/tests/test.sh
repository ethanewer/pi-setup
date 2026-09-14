#!/bin/bash
# Verifier for mizzen-seaboard (v4.3 upstream-clone family): proves the
# agent's fix in the real psycopg tree at /app/src. Steps: (0) integrity
# anchors - the sha256 pins recorded at image build time for the golden
# regression test (/opt/golden), the pristine pre-fix package
# (/opt/prefix/psycopg) and the toolchain detect any substitution; (1)
# provenance - HEAD is still the pinned parent commit and the upstream fix
# commit is not reachable from this clone's object store, and the index is
# sane (no gitlink entries, modes restricted to 100644/100755); (2) scope -
# a FILESYSTEM-DRIVEN walk of /app/src (immune to .git/info/exclude
# hiding): every tracked file must be byte-identical to the parent commit
# except the single source file where the bug lives, no file may be added,
# deleted, renamed or turned into a symlink, and the index oid must equal
# the parent blob for every non-bug file; (3) deliverables - /app/repro.sh
# and /app/summary.md exist and are non-empty; (4) the agent's own
# reproduction must FAIL against the pristine pre-fix package baked at
# /opt/prefix/psycopg and PASS against the repaired tree via
# PSYCOPG_PACKAGE_DIR=/app/src/psycopg, with direct -S probes proving the
# pristine package still exhibits the bug and (NEW) that the TREE's own
# bytes resolve the aliases correctly (site hooks such as sitecustomize / 
# .pth / usercustomize cannot influence -S probes, so a runtime-only patch
# with the real source untouched scores 0 here); (5) the installed library
# is refreshed from the delivered tree and verified under -S to be the
# fixed one (import the library the agent installed); (6) the upstream
# project's own regression test for this bug (extracted upstream at image
# build time into /opt/golden, sha256-pinned) is planted over the tree's
# copy and the whole file must pass all 21 tests, including both MSKANJI
# rows - run under python3 -S so no site-level hook can fake the run;
# (7) previously-existing project test files test_conninfo.py and
# test_sql.py must stay green (43 and 44 passed respectively, the latter
# with 80 --test-dsn skips), also under -S; (8) two authored hidden pytest
# files exercise the same code path from inputs the upstream test does not
# use, also under -S.
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

PARENT=19b58ffd057f23a5dc10fac5b949792f584e0494
FIX=793cd8786373f5d1564493e35283b0d80cb67d96
ALLOWED_FILE=psycopg/psycopg/_encodings.py
SP=/usr/local/lib/python3.12/site-packages

# All graded python runs use -S (site module disabled) so no sitecustomize,
# .pth or usercustomize hook can alter graded behaviour; site-packages is put
# on sys.path explicitly so pypi-installed deps resolve.
pytest_cmd_py='import sys; sys.path[:0] = ["/usr/local/lib/python3.12/site-packages"]; import pytest; raise SystemExit(pytest.main([*sys.argv[1:]]))'
runpytest() {  # args... -> python3 -S running real pytest on args...
    python3 -S -c "$pytest_cmd_py" "$@"
}

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors (golden test, pristine pre-fix package, toolchain).
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-psycopg.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, prefix-package or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: still detached at the pinned parent commit; the upstream fix
#    commit must not be reachable from this object store; index must be sane.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope. Filesystem-driven: walk every path under /app/src (excluding
#    .git internals and python bytecode caches). This catches files hidden
#    from `git status` via .git/info/exclude or .gitignore, extra files,
#    deleted files, symlinks, and any worktree divergence - independently of
#    whatever the agent did to the index.
holdon=1
while IFS= read -r -d '' p; do
    rel=${p#/app/src/}
    case "$rel" in
        .git/*|.git) continue ;;
        psycopg/psycopg/_encodings.py) continue ;;
        .pytest_cache/*|*/__pycache__/*|*.pyc) continue ;;
    esac
    if [ -L "$p" ]; then
        echo "unexpected symlink: $rel" >> "$LOG"; holdon=0; continue
    fi
    if [ -f "$p" ]; then
        if ! git ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
            # untracked: allowed only when ignored by a TRACKED .gitignore
            # file of the parent tree (build byproducts such as *.egg-info
            # and build/lib); anything ignored by .git/info/exclude or a
            # global excludes file is agent-editable and FAILS.
            src=$(git check-ignore -v --no-index -- "$p" 2>/dev/null | head -1 || true)
            case "$src" in
                *.gitignore:*)
                    ig=${src%%:*}
                    if git ls-files --error-unmatch -- "$ig" >/dev/null 2>&1; then
                        :
                    else
                        echo "untracked file ignored by non-tracked ignore file ($ig): $rel" >> "$LOG"; holdon=0
                    fi
                    ;;
                "")
                    echo "untracked file in tree: $rel" >> "$LOG"; holdon=0 ;;
                *)
                    echo "untracked file ignored by non-tree source ($src): $rel" >> "$LOG"; holdon=0 ;;
            esac
            continue
        fi
        want=$(git rev-parse "$PARENT:$rel" 2>/dev/null || true)
        if [ -z "$want" ]; then
            echo "tracked file not in parent tree: $rel" >> "$LOG"; holdon=0; continue
        fi
        have=$(git hash-object -- "$p" 2>/dev/null || true)
        if [ -z "$have" ] || [ "$have" != "$want" ]; then
            echo "worktree bytes differ from parent for: $rel" >> "$LOG"; holdon=0
        fi
    elif [ -d "$p" ]; then
        # a directory that the parent tree does not have is an added dir;
        # empty parent-tracked? parent has no empty dirs tracked, so a dir
        # not containing anything special is acceptable only if it existed
        # at parent as a path prefix of tracked files.
        :
    else
        echo "unexpected non-file entry: $rel" >> "$LOG"; holdon=0
    fi
done < <(find /app/src -path /app/src/.git -prune -o -print0)
# every tracked file must also exist on disk with the parent's bytes
while IFS= read -r rel; do
    case "$rel" in
        psycopg/psycopg/_encodings.py) continue ;;
    esac
    [ -e "/app/src/$rel" ] || { echo "tracked file missing from worktree: $rel" >> "$LOG"; holdon=0; }
done < <(git ls-files)
# every tracked index entry must be a regular file (mode 100644 or 100755)
# with the parent blob's oid, and the worktree file must hash to the same
# blob: this defeats index-space games (gitlink entries, cacheinfo spoofs).
while IFS=$'\t' read -r meta rel; do
    [ -n "$rel" ] || continue
    read -r mode oid _stg <<< "$meta"
    [ "$mode" = "100644" ] || [ "$mode" = "100755" ] || {
        echo "index mode $mode for $rel is not a plain file" >> "$LOG"; holdon=0; continue
    }
    case "$rel" in
        psycopg/psycopg/_encodings.py) continue ;;
    esac
    want=$(git rev-parse "$PARENT:$rel" 2>/dev/null || true)
    if [ -z "$want" ] || [ "$oid" != "$want" ]; then
        echo "index oid mismatch for tracked file: $rel" >> "$LOG"; holdon=0
    fi
done < <(git ls-files -s)
if [ "$holdon" != "1" ]; then
    tail -40 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# the one allowed source file must actually differ from the parent commit
if git diff --quiet -- "$ALLOWED_FILE"; then
    fail "the bug's source file is unmodified (no fix attempted)"
fi

# 3) deliverables.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the agent's own reproduction, both directions. Against the pristine
#    pre-fix package (default PSYCOPG_PACKAGE_DIR=/opt/prefix/psycopg) it
#    must FAIL; against the repaired tree it must PASS. (The agent's script
#    runs with site enabled - the direct -S probes below are what pin the
#    actual behaviour of the bytes on disk.)
if ( cd /tmp && timeout 180 bash /app/repro.sh > /tmp/repro_prefix.out 2>&1 ); then
    echo "agent repro passed against the PRE-FIX package (expected failure); stdout:" >> "$LOG"
    head -15 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pristine pre-fix package (see $LOG)"
fi
if ! ( cd /tmp && timeout 180 env PSYCOPG_PACKAGE_DIR=/app/src/psycopg bash /app/repro.sh > /tmp/repro_fixed.out 2>&1 ); then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -15 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi

# sanity probes, run with python3 -S (no site hooks):
#  (a) the pristine package baked in the image is genuinely the pre-fix code
#      (the MSKANJI alias silently falls back to utf-8 there);
#  (b) the TREE's own bytes (/app/src/psycopg) resolve the alias - this is
#      the keystone check that no runtime patch can pass with the real
#      source untouched.
probe=$(cd /tmp && PYTHONPATH="/opt/prefix/psycopg:$SP" python3 -S -c "from psycopg import _encodings as e; print(e.conninfo_encoding('user=foo dbname=bar client_encoding=MSKANJI'))" 2>&1)
if [ "$probe" != "utf-8" ]; then
    fail "pristine pre-fix package does not exhibit the bug (probe returned: $probe)"
fi
tprobe=$(cd /tmp && python3 -S -c "import sys; sys.path[:0]=['/app/src/psycopg','$SP']; from psycopg import _encodings as e; print(e.conninfo_encoding('user=foo dbname=bar client_encoding=MSKANJI'))" 2>&1)
if [ "$tprobe" != "shift_jis" ]; then
    fail "the tree's own bytes do not resolve MSKANJI to shift_jis (got: $tprobe); fix the real source"
fi

# 5) refresh the installed library from the delivered tree and verify the
#    installed package is the fixed one, under -S. The verifier executes the
#    project's own test runner on a site-packages copy refreshed FROM THE
#    TREE, so an agent that only patched site-packages (or shipped a wrapper
#    elsewhere) gains nothing: the graded bytes are the tree's.
[ -d "$SP/psycopg" ] || fail "site-packages psycopg is missing"
rm -rf "$SP/psycopg" || fail "cannot replace site-packages psycopg"
cp -a /app/src/psycopg/psycopg "$SP/psycopg" || fail "cannot refresh site-packages from the tree"
find "$SP/psycopg" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
inst=$(cd /tmp && python3 -S -c "import sys; sys.path[:0]=['$SP']; from psycopg import _encodings as e; print(e.conninfo_encoding('user=foo dbname=bar client_encoding=MSKANJI'))" 2>&1)
if [ "$inst" != "shift_jis" ]; then
    fail "installed library does not resolve MSKANJI to shift_jis (got: $inst)"
fi

# 6) plant the upstream regression test (golden bytes, extracted upstream at
#    image build time and sha256-pinned; never part of this task tree) over
#    the tree's copy, then run the whole file under -S.
cp /opt/golden/test_encodings.py tests/test_encodings.py || fail "cannot plant golden test"
if ! runpytest tests/test_encodings.py -v -o cache_dir=/tmp/pyc-golden > "$LOG.golden" 2>&1; then
    tail -40 "$LOG.golden" >&2
    fail "golden test file did not pass (see $LOG.golden)"
fi
grep -q "21 passed" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "golden test file did not report 21 passed (see $LOG.golden)"
}
grep -Fq "client_encoding=MSKANJI-shift_jis] PASSED" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the MSKANJI golden row did not run and pass (see $LOG.golden)"
}
grep -Fq "client_encoding=mskanji-shift_jis] PASSED" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the mskanji golden row did not run and pass (see $LOG.golden)"
}

# 7) previously-existing project test files must stay green (the scope check
#    above guarantees they are byte-identical to the parent commit, so a
#    green run proves the fix broke nothing else).
if ! runpytest tests/test_conninfo.py -q -o cache_dir=/tmp/pyc-conn > "$LOG.conninfo" 2>&1; then
    tail -30 "$LOG.conninfo" >&2
    fail "test_conninfo.py did not pass (see $LOG.conninfo)"
fi
grep -q "43 passed" "$LOG.conninfo" || {
    tail -20 "$LOG.conninfo" >&2
    fail "test_conninfo.py did not report 43 passed (see $LOG.conninfo)"
}
if ! runpytest tests/test_sql.py -q -o cache_dir=/tmp/pyc-sql > "$LOG.sql" 2>&1; then
    tail -30 "$LOG.sql" >&2
    fail "test_sql.py did not pass (see $LOG.sql)"
fi
grep -q "44 passed, 80 skipped" "$LOG.sql" || {
    tail -20 "$LOG.sql" >&2
    fail "test_sql.py did not report 44 passed / 80 skipped (see $LOG.sql)"
}

# 8) two authored hidden cases exercising the same code path from inputs the
#    upstream regression test does not use (alias spellings, conninfo syntax
#    variants, direct pg2pyenc calls). Each must run and pass.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    src=$(ls "$case"test_*.py 2>/dev/null | head -1)
    [ -n "$src" ] || fail "hidden case $name: missing test_*.py"
    dst="/app/src/tests/$(basename "$src")"
    cp "$src" "$dst" || fail "hidden case $name: cannot copy test file"
    log="$LOG.hidden.$name"
    if ! runpytest "$dst" -q -o cache_dir=/tmp/pyc-hc > "$log" 2>&1; then
        tail -30 "$log" >&2
        fail "hidden case $name did not pass (see $log)"
    fi
    grep -q "passed" "$log" || fail "hidden case $name: no passing run reported (see $log)"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected 2"

echo "PASS: provenance, fix-unreachable, index sanity, filesystem scope, deliverables, repro both directions, pristine-package sanity, tree-byte probe, installed-library refresh, upstream regression test (21/21 incl. MSKANJI rows), existing suites, and hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0