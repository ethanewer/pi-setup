#!/bin/bash
# ---------------------------------------------------------------------------
# Verifier for oakum-landfall: the agent must fix the wheel-name
# normalisation defect in the real setuptools tree at /app/src and write
# /app/reproduce.py. Checks, in order:
#  0. cd /app/src; the shipped golden regression-test files still byte-match
#     the sha256 pins recorded at image build time (tamper with the tests and
#     you earn 0).
#  1. provenance: HEAD still the pinned parent commit; the upstream fix
#     commit is not reachable from this object store; the working tree
#     differs from the pinned commit only in the two source files the fix
#     requires plus the two golden test files; no stray untracked files
#     (python cache dirs excepted) under /app/src.
#  2. /app/reproduce.py exists, non-empty.
#  3. the reproduction FAILS against a pristine pre-fix snapshot of the tree
#     baked at /opt/pristine.tar.gz (proves the symptom is real and the
#     reproduction targets it).
#  4. the reproduction PASSES against the repaired tree.
#  5. the project's own regression tests for this behaviour (extracted from
#     the fix commit into the tree at image build time) and the still-
#     existing area tests (full test_bdist_wheel.py, full test_dist_info.py,
#     and the doctests of the normalisation module) all pass.
#  6. authored hidden cases exercise the same code path from inputs the
#     upstream tests do not use; each is also run against the pristine tree
#     where it must FAIL.
# Reward is binary: 1 iff every step above passes, else 0.
# ---------------------------------------------------------------------------
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

PARENT=d8da7dfaa0cef4a69ee21d9406391651c4dc5ce4
FIX=9559193e1eb12aee0a9eb6cc754e519e6e09ecb4

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors: the two golden regression-test files the image
#    shipped must still be byte-identical to the build-time pins.
sha256sum -c /opt/pins/golden-bdist.sha256 >/dev/null 2>&1 \
    || fail "setuptools/tests/test_bdist_wheel.py does not match the pinned golden copy"
sha256sum -c /opt/pins/golden-distinfo.sha256 >/dev/null 2>&1 \
    || fail "setuptools/tests/test_dist_info.py does not match the pinned golden copy"

# 1) provenance
[ "$(git rev-parse HEAD)" = "$PARENT" ] || fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT (the tree must stay detached at the parent commit)"
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable in this object store (agent must not fetch or graft it)"
fi

# Tracked files may differ from the parent commit ONLY where the fix lives
# (the two source files) and in the two golden test files.
changed=$(git diff --name-only "$PARENT" -- . 2>/dev/null || true)
if [ -n "$changed" ]; then
    for f in $changed; do
        case "$f" in
            setuptools/_normalization.py|setuptools/command/bdist_wheel.py|setuptools/tests/test_bdist_wheel.py|setuptools/tests/test_dist_info.py) ;;
            *) fail "tracked file changed beyond the fix: $f" ;;
        esac
    done
fi

stray=$(git status --porcelain | awk '$1 == "??" { print $2 }' | grep -v '__pycache__' | grep -v '\.pyc$' | grep -v '^\.pytest_cache' | grep -v '\.egg-info' || true)
[ -z "$stray" ] || fail "stray untracked files under /app/src: $stray"

# 2) deliverable
[ -s /app/reproduce.py ] || fail "/app/reproduce.py is missing or empty"

# the installed setuptools must BE the shipped tree (editable install): an
# agent that upgrades/reinstalls from elsewhere and never fixes /app/src has
# not done the task, and the graded suites would then validate a package the
# tree did not produce.
if ! (cd /tmp && python3 -c "import setuptools; assert setuptools.__file__.startswith('/app/src/'), setuptools.__file__") 2>/dev/null; then
    fail "the importable setuptools is not the /app/src tree (installed editable); upgrading or reinstalling from elsewhere is not a fix"
fi

# 3) reproduction must FAIL against the pristine pre-fix tree
pristine=$(mktemp -d /tmp/oakum-pristine.XXXXXX) || fail "could not create scratch dir"
tar xzf /opt/pristine.tar.gz -C "$pristine" || fail "pristine pre-fix snapshot is corrupt"
if PYTHONPATH="$pristine/src" python3 /app/reproduce.py >/tmp/repro-prefix.log 2>&1; then
    fail "reproduce.py exited 0 against the pristine pre-fix tree (it must fail there); tail: $(tail -3 /tmp/repro-prefix.log)"
fi

# 4) reproduction must PASS against the repaired tree
if ! python3 /app/reproduce.py >/tmp/repro-fixed.log 2>&1; then
    fail "reproduce.py failed against the repaired tree; tail: $(tail -10 /tmp/repro-fixed.log)"
fi

# 5) the project's own tests, run from the tree with the project's pytest
#    configuration (includes --doctest-modules)
if ! python3 -m pytest -q \
        setuptools/tests/test_bdist_wheel.py \
        setuptools/tests/test_dist_info.py \
        > /tmp/oakum-suite.log 2>&1; then
    fail "project suite (test_bdist_wheel.py, test_dist_info.py) not green; tail: $(tail -6 /tmp/oakum-suite.log)"
fi
if ! python3 -m pytest -q setuptools/_normalization.py >/tmp/oakum-norm.log 2>&1; then
    fail "normalisation-module doctests not green; tail: $(tail -6 /tmp/oakum-norm.log)"
fi

# 7) isolated (-S) probe: re-verify the canonical rule straight from the tree
#    in a process with NO site machinery, so no sitecustomize/user-site hook
#    injected anywhere outside the tree can satisfy it. Checks BOTH name
#    helpers the two code paths use (the shared helper and the one the wheel
#    command calls) over the golden and hidden inputs. Only a real fix in
#    /app/src can pass this.
cat > /tmp/oakum_isoprobe.py <<'PY'
import sys
sys.path.append("/usr/local/lib/python3.12/site-packages")
import setuptools
assert setuptools.__file__.startswith("/app/src/"), setuptools.__file__
from setuptools._normalization import safer_name as shared
from setuptools.command import bdist_wheel as bw

CASE_TABLE = {
    "unicode.dist": "unicode_dist",          # golden test input
    "my.proj": "my_proj",                    # golden test input (dist_info compat)
    "Camel.Case": "camel_case",              # hidden h1/h2 inputs
    "x.y.z": "x_y_z",
    "UPPER.Name": "upper_name",
    "a.b-c_d": "a_b_c_d",
    "alpha.beta--Gamma": "alpha_beta_gamma",
    "weird.name--With--Dashes": "weird_name_with_dashes",
}
bad = {}
for name, canon in CASE_TABLE.items():
    if shared(name) != canon:
        bad["setuptools._normalization.safer_name(%r)" % name] = shared(name)
    if getattr(bw, "safer_name", shared)(name) != canon:
        bad["bdist_wheel.safer_name(%r)" % name] = getattr(bw, "safer_name", shared)(name)
if bad:
    print("not canonical in site-less process:", bad)
    raise SystemExit(1)
print("ok: isolated probe: canonical rule implemented in the tree (both helpers)")
PY
if ! PYTHONPATH=/app/src python3 -S /tmp/oakum_isoprobe.py >>"$LOG" 2>&1; then
    fail "isolated (-S) probe: the canonical rule is NOT implemented in the tree; tail: $(tail -4 "$LOG")"
fi

# 6) hidden cases: must pass against the repaired tree and must FAIL against
#    the pristine pre-fix tree (proving they exercise the defect)
if PYTHONPATH="$pristine/src" python3 /tests/hidden/h1-direct-import/run.py >/tmp/h1-prefix.log 2>&1; then
    fail "hidden case h1 passed against the pristine pre-fix tree (it must fail there)"
fi
if ! python3 /tests/hidden/h1-direct-import/run.py >/tmp/h1.log 2>&1; then
    fail "hidden case h1 failed against the repaired tree; tail: $(tail -8 /tmp/h1.log)"
fi
if PYTHONPATH="$pristine/src" python3 /tests/hidden/h2-wheelbuild/run.py >/tmp/h2-prefix.log 2>&1; then
    fail "hidden case h2 passed against the pristine pre-fix tree (it must fail there)"
fi
if ! python3 /tests/hidden/h2-wheelbuild/run.py >/tmp/h2.log 2>&1; then
    fail "hidden case h2 failed against the repaired tree; tail: $(tail -8 /tmp/h2.log)"
fi

rm -rf "$pristine"

echo "all checks passed"
echo 1 > /logs/verifier/reward.txt