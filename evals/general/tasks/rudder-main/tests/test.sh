#!/bin/bash
# Verifier for rudder-main: proves the agent's fix in the real statsmodels
# tree at /app/src by (1) asserting the verifier's own trust anchors (sha256
# pins recorded at image build time for the golden regression test, the
# pristine pre-fix module, and the toolchain), (2) asserting provenance (HEAD
# still the pinned parent commit; the upstream fix commit is not reachable
# from this object store; every tracked file except
# statsmodels/regression/linear_model.py is byte-identical to the parent
# commit; the importable library resolves inside /app/src), (3) requiring
# /app/repro.py and /app/summary.md, (4) running the agent's reproduction
# against the repaired tree (must pass, printing REPRO OK) and against the
# pristine pre-fix module swapped in from /opt/prefix (must fail - proving the
# symptom is real and the reproduction targets it), plus a direct canonical
# symptom check in both directions, (5) planting the project's own regression
# test (the fix-commit test_regression.py extracted at image build time into
# /opt/golden, sha256-pinned) and running it plus the whole project test
# module, and (6) running four authored hidden cases that reach the same code
# path from inputs the upstream test does not use.
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

PARENT=c67d83dc9befc8927753c207e3571443b42cc749
FIX=3c7f8f8118160379e880d9d437d22edbb7ef9a9b

export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1

purge_pycache() {
    find /app/src/statsmodels -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
}

# 0) integrity anchors. A root agent could otherwise substitute the golden
#    test, the pre-fix module, or the interpreter/toolchain with stubs that
#    fake a green run; the pins recorded at image build time detect any
#    substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-lm.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix module or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: HEAD must still be the pinned parent commit, the upstream
#    fix commit must not be reachable from this object store (an agent that
#    fetched or grafted the fix earns 0; the fix direction must come from the
#    agent's own work), and exactly one tracked file may differ from the
#    parent commit: statsmodels/regression/linear_model.py.
cd /app/src || fail "/app/src is missing"
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit ${FIX} is reachable from /app/src"
fi
if [ "$(git rev-list --all | wc -l)" != "1" ]; then
    fail "object store holds more than one commit (history was fetched)"
fi
if git ls-files -v | grep -q '^[a-z]'; then
    fail "assume-unchanged/skip-worktree index flags present (git status is blind to them)"
fi
status=$(git status --porcelain)
# test-data.xml is a byproduct the project's own pytest run leaves in cwd
# (created when the agent follows the recommended test loop); it is not part
# of the pinned tree and is ignored. Everything else must be exactly
# linear_model.py.
normalized=$(printf '%s\n' "$status" | sed 's/^.. //' | grep -v '^$' | grep -v '^test-data.xml$' | sort)
if [ "$normalized" != "statsmodels/regression/linear_model.py" ]; then
    fail "scope violation: changed/added/removed paths = [$normalized] (only statsmodels/regression/linear_model.py may differ)"
fi
if ! python -c "import statsmodels.regression.linear_model as lm; assert lm.__file__.startswith('/app/src'), lm.__file__; print(lm.__file__)" >/dev/null 2>&1; then
    fail "importable statsmodels does not resolve inside /app/src (shadow install?)"
fi

# 2) deliverables exist and are non-empty.
[ -s /app/repro.py ] || fail "/app/repro.py missing or empty"
[ -s /app/summary.md ] || fail "/app/summary.md missing or empty"

# 3) the agent's reproduction against the repaired tree must pass and print
#    REPRO OK.
if ! python /app/repro.py > /tmp/repro_fixed.log 2>&1; then
    echo "repro against repaired tree failed; tail:" >> "$LOG"
    tail -8 /tmp/repro_fixed.log >> "$LOG"
    fail "agent reproduction failed against the repaired tree"
fi
if ! grep -q "REPRO OK" /tmp/repro_fixed.log; then
    fail "agent reproduction did not print REPRO OK"
fi

# 4) direct canonical symptom check on the repaired tree: a fixed-scale fit
#    must report the supplied scale.
cat > /tmp/canonical.py <<'PY'
import numpy as np
import numpy.testing as npt
np.random.seed(0)
from statsmodels.regression.linear_model import OLS
from statsmodels.tools.tools import add_constant
scale = 5.0
X = add_constant(np.random.rand(50, 2))
y = np.dot(X, [1, 2, 3]) + np.random.randn(50)
res = OLS(y, X).fit(cov_type="fixed scale", cov_kwds={"scale": scale})
npt.assert_allclose(res.scale, scale)
npt.assert_allclose(res.resid_pearson, res.resid / np.sqrt(scale))
print("CANONICAL FIXED-TREE OK")
PY
if ! python /tmp/canonical.py > /tmp/canonical_fixed.log 2>&1; then
    fail "canonical fixed-scale check failed on the repaired tree"
fi

# 5) pre-fix direction: swap the pristine parent module in, the reproduction
#    and the canonical check must FAIL (proving the symptom is real in this
#    image and that the reproduction targets it); then restore the agent's
#    module byte-exactly.
cp /app/src/statsmodels/regression/linear_model.py /tmp/lm_agent.py
cp /opt/prefix/linear_model_parent.py /app/src/statsmodels/regression/linear_model.py
purge_pycache
if python /app/repro.py > /tmp/repro_prefix.log 2>&1; then
    cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
    purge_pycache
    fail "agent reproduction PASSED against the pristine pre-fix module (it does not target the bug)"
fi
if grep -q "REPRO OK" /tmp/repro_prefix.log; then
    cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
    purge_pycache
    fail "agent reproduction printed REPRO OK on the pristine pre-fix module"
fi
if python /tmp/canonical.py > /tmp/canonical_prefix.log 2>&1; then
    cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
    purge_pycache
    fail "canonical fixed-scale check PASSED on the pristine pre-fix module (bug absent?)"
fi
cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
purge_pycache
if ! cmp -s /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py; then
    fail "failed to restore the agent's linear_model module after the pre-fix probe"
fi

# 6) plant the project's own regression test (added upstream with the fix,
#    extracted at image build time through a throwaway clone; the whole
#    fix-commit test_regression.py is a strict superset of the parent's) and
#    require it to pass.
cp /opt/golden/test_regression.py /app/src/statsmodels/regression/tests/test_regression.py
if ! python -m pytest statsmodels/regression/tests/test_regression.py \
        -k test_ols_wls_fixed_scale -q -p no:cacheprovider \
        > /tmp/golden.log 2>&1; then
    echo "golden test output tail:" >> "$LOG"
    tail -10 /tmp/golden.log >> "$LOG"
    fail "project's own regression test test_ols_wls_fixed_scale failed"
fi
if ! grep -q "1 passed" /tmp/golden.log; then
    fail "golden regression test did not report 1 passed"
fi

# 7) the whole project test module must stay green (369 existing tests +
#    the planted regression test = 370 passed, 2 skipped).
if ! python -m pytest statsmodels/regression/tests/test_regression.py \
        -q -p no:cacheprovider > /tmp/whole.log 2>&1; then
    echo "whole-module pytest tail:" >> "$LOG"
    tail -12 /tmp/whole.log >> "$LOG"
    fail "project test module statsmodels/regression/tests/test_regression.py is not green"
fi
if ! grep -q "370 passed, 2 skipped" /tmp/whole.log; then
    echo "whole-module pytest tail:" >> "$LOG"
    tail -5 /tmp/whole.log >> "$LOG"
    fail "project test module did not report 370 passed, 2 skipped"
fi

# 8) authored hidden cases: same code path, upstream-unused inputs, each
#    asserted against an independent NumPy computation.
hidden_ok=1
for d in /tests/hidden/h*/; do
    case_dir=${d%/}
    if ! bash "$case_dir/run.sh" > /tmp/hidden_$(basename "$case_dir").log 2>&1; then
        echo "hidden case $(basename "$case_dir") failed; tail:" >> "$LOG"
        tail -8 /tmp/hidden_$(basename "$case_dir").log >> "$LOG"
        hidden_ok=0
        break
    fi
    if ! grep -q "HIDDEN OK" /tmp/hidden_$(basename "$case_dir").log; then
        echo "hidden case $(basename "$case_dir") did not print HIDDEN OK" >> "$LOG"
        hidden_ok=0
        break
    fi
done
if [ "$hidden_ok" != "1" ]; then
    fail "one or more hidden cases failed"
fi

echo 1 > /logs/verifier/reward.txt
echo "VERIFIED: all checks passed; reward 1"
exit 0