#!/bin/bash
# thole-ground verifier.
#
# Proves, in order:
#   1. the deliverable /app/reproduce.py exists and honours its documented
#      output contract on the REPAIRED tree (exit 0, BUILT/ROUNDTRIP lines,
#      BUILT URL contains no e/E, ROUNDTRIP value equals the input);
#   2. the SAME deliverable fails against the read-only pristine PRE-fix tree
#      and its BUILT line there shows the scientific-notation URL -- the
#      reproduction is genuine, not a script that always succeeds;
#   3. /app/src is the pinned werkzeug checkout and the fix commit's object
#      is NOT reachable from it (the build fetched the parent by SHA only, so
#      the answer was never in the repo the agent received);
#   4. the pristine tree is byte-intact at the parent commit and the tests/
#      directory under /app/src is byte-identical to the shipped snapshot
#      (no deleting/editing tests to make the suite green);
#   5. the project's OWN regression test (extracted from the fix commit at
#      build time) passes on the repaired tree and fails on the pristine one;
#   6. every hidden case passes on the repaired tree and fails on the
#      pristine one (hidden inputs differ from the upstream test's);
#   7. the FULL upstream suite (983 tests) is green on the repaired tree.
# Reward is binary, 1 only if every check passes, written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

PARENT_SHA=b97e13cc74d8a45dca260d4037edd7d1f5094042
FIX_SHA=f88164a271dd3e86a3241389ddc5c53eca4b9e4a
# sha256 of the pristine parent-tree converters.py; recomputed at build time.
PRISTINE_HASH=8aaa5e7bf9808ebd6819bab47adba3605f4f883bf953b0e03640111d79cc21dd

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# ---- 1. deliverable contract on the repaired tree -------------------------
if [ ! -f /app/reproduce.py ]; then
    fail "/app/reproduce.py missing"
else
    for v in 0.00001 1e20 2.5e-07 5.0; do
        out=$(python3 /app/reproduce.py "$v" 2>&1); rc=$?
        if [ "$rc" -ne 0 ]; then
            fail "reproduce.py $v exited $rc on the repaired tree; output:"; printf '    %s\n' "$out" >&2
            continue
        fi
        built=$(printf '%s\n' "$out" | sed -n 's/^BUILT //p' | head -1)
        rt=$(printf '%s\n' "$out" | sed -n 's/^ROUNDTRIP //p' | head -1)
        if [ -z "$built" ] || printf '%s' "$built" | grep -q '[eE]'; then
            fail "reproduce.py $v: BUILT line missing or scientific: $out"
        fi
        if [ -z "$rt" ]; then
            fail "reproduce.py $v: ROUNDTRIP line missing: $out"
        else
            ok=$(python3 - "$rt" "$v" <<'PY'
import sys
parts = sys.argv[1].split()
value = float(sys.argv[2])
if len(parts) == 2 and parts[0] == 'a' and float(parts[1]) == value:
    print('ok')
else:
    print('bad')
PY
            )
            [ "$ok" = ok ] || fail "reproduce.py $v: ROUNDTRIP inconsistent: $out"
        fi
    done
    echo "reproduction on repaired tree: checked"
fi

# ---- 2. the same deliverable against the pristine pre-fix tree ------------
if [ -d /opt/pristine ]; then
    for v in 0.00001 1e20; do
        out=$(cd / && PYTHONPATH=/opt/pristine/src python3 /app/reproduce.py "$v" 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then
            fail "reproduce.py $v exited 0 on the pristine pre-fix tree (reproduction is not honest)"
        fi
        if ! printf '%s\n' "$out" | grep -q '^BUILT .*[eE]'; then
            fail "reproduce.py $v: pristine-tree output does not show a scientific-notation BUILT URL:"; printf '    %s\n' "$out" >&2
        fi
    done
    echo "reproduction on pristine pre-fix tree: fails as required"
else
    fail "/opt/pristine missing"
fi

# ---- 3. checkout integrity ------------------------------------------------
if [ ! -d /app/src/.git ]; then
    fail "/app/src is not a git checkout"
else
    if ! git -C /app/src cat-file -e "$PARENT_SHA^{commit}" 2>/dev/null; then
        fail "parent commit object not known to /app/src"
    fi
    if git -C /app/src cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then
        fail "fix commit object IS reachable from /app/src (the answer leaked into the repo)"
    fi
fi

# ---- 4. pristine tree and suite-bytes integrity ---------------------------
# A monitor-patch bypass: a sitecustomize/usercustomize dropped in the
# verifier's CWD would monkeypatch the installed library at interpreter
# startup without touching /app/src. Reject it (the fix must live in the
# library itself).
for sc in /app/sitecustomize.py /app/src/sitecustomize.py \
          /app/usercustomize.py /app/src/usercustomize.py; do
    [ -e "$sc" ] && fail "startup-hook file present: $sc (monkeypatch bypass)"
done

if [ -f /opt/pristine/src/werkzeug/routing/converters.py ]; then
    h=$(sha256sum /opt/pristine/src/werkzeug/routing/converters.py | cut -d' ' -f1)
    [ "$h" = "$PRISTINE_HASH" ] || fail "pristine converters.py modified (hash $h)"
    ph=$(git -C /opt/pristine rev-parse HEAD 2>/dev/null || echo none)
    [ "$ph" = "$PARENT_SHA" ] || fail "pristine tree not at parent (HEAD $ph)"
else
    fail "/opt/pristine tree missing"
fi
if [ -f /opt/tests.sha256 ] && [ -d /app/src/tests ]; then
    if (cd /app/src \
        && find tests -type f ! -name '*.pyc' ! -path '*/__pycache__/*' -print0 \
             | sort -z | xargs -0 sha256sum | diff -q - /opt/tests.sha256 >/tmp/testsdiff.log 2>&1); then
        echo "tests/ directory byte-identical to snapshot"
    else
        fail "tests/ directory differs from the shipped snapshot (tests deleted or edited)"; head -5 /tmp/testsdiff.log >&2
    fi
else
    fail "/opt/tests.sha256 or /app/src/tests missing"
fi

# ---- 5. golden test: pass on repaired, fail on pristine -------------------
if [ -f /opt/golden/test_float_no_scientific.py ]; then
    if (cd /app/src && python3 -m pytest /opt/golden/test_float_no_scientific.py -q -p no:cacheprovider >/tmp/golden_ok.log 2>&1); then
        echo "golden test on repaired tree: PASS"
    else
        fail "golden test did not pass on the repaired tree"; tail -n 6 /tmp/golden_ok.log >&2
    fi
    if (cd /opt/pristine && PYTHONPATH=/opt/pristine/src python3 -m pytest /opt/golden/test_float_no_scientific.py -q -p no:cacheprovider >/tmp/golden_pristine.log 2>&1); then
        fail "golden test PASSES on the pristine pre-fix tree (should fail there)"
    else
        echo "golden test on pristine tree: fails as required"
    fi
else
    fail "/opt/golden/test_float_no_scientific.py missing"
fi

# ---- 6. hidden cases: pass on repaired, fail on pristine ------------------
for d in /tests/hidden/*/; do
    run="$d/run.py"
    [ -f "$run" ] || continue
    name=$(basename "$d")
    if (cd /app && python3 "$run" >/tmp/hid_ok.log 2>&1); then
        echo "hidden $name on repaired tree: PASS"
    else
        fail "hidden $name failed on the repaired tree"; tail -n 8 /tmp/hid_ok.log >&2
    fi
    if [ -d /opt/pristine ]; then
        if (cd /app && PYTHONPATH=/opt/pristine/src python3 "$run" >/tmp/hid_pristine.log 2>&1); then
            fail "hidden $name PASSES on the pristine tree (does not discriminate the bug)"
        else
            echo "hidden $name on pristine tree: fails as required"
        fi
    fi
done

# ---- 7. full upstream suite on the repaired tree --------------------------
if (cd /app/src && python3 -m pytest -q -p no:cacheprovider >/tmp/full.log 2>&1); then
    echo "full upstream suite: PASS ($(tail -1 /tmp/full.log))"
else
    fail "full upstream suite not green"; tail -n 15 /tmp/full.log >&2
fi

# ---- reward ---------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
    echo "REWARD 1: every check passed ($failures failures)"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: $failures check(s) failed"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0