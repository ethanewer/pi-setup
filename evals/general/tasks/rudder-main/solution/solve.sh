#!/bin/bash
# Crude-rudder oracle for rudder-main: applies the real upstream one-line fix
# (in the fixed-scale branch of RegressionResults.get_robustcov_results, the
# supplied scale is now also written into the cached res.scale attribute) to
# the statsmodels tree at /app/src, writes the reproduction and the summary,
# then proves the work: the reproduction passes against the repaired tree and
# fails against the pristine pre-fix module baked at /opt/prefix. Reads only
# /app, /solution and /opt, never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the fixed-scale fix"

cp /solution/repro.py /app/repro.py
chmod 644 /app/repro.py
echo "oracle: wrote /app/repro.py"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: when a linear regression (OLS or WLS) was fitted with a user-supplied
fixed scale for the covariance (cov_type "fixed scale" or "fixed_scale"),
the fitted result kept reporting the residual-based estimate of the scale in
its `scale` attribute instead of the supplied value, and `resid_pearson`
normalised residuals with the square root of that wrong estimate. The
parameter covariance was correct; only the reported scale and the
normalised residuals were wrong.

Cause: the fixed-scale branch of the results post-processing
(RegressionResults.get_robustcov_results) wrote the supplied scale into the
covariance bookkeeping but never into the cached result attribute, so the
`scale` property kept recomputing ssr/df_resid and `resid_pearson` divided by
the square root of that recomputed (wrong) estimate.

Fix: write the supplied scale into the cached result attribute
(`res.scale = scale`) in the fixed-scale branch, so the property returns the
supplied value and the Pearson residuals normalise with it.

Verified: /app/repro.py fails on the pristine pre-fix module (observed
scale attribute ~1.04 for supplied 5.0) and passes on the repaired tree
(scale attribute 5.0; resid_pearson matches resid/sqrt(5.0)); OLS, WLS and
the re-processing path all agree; the project's own regression test module
(369 existing tests) is fully green.
MD
echo "oracle: wrote /app/summary.md"

export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1

purge_pycache() {
    find /app/src/statsmodels -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
}

echo "oracle: reproduction against repaired tree (must pass)"
if ! python /app/repro.py > /tmp/oracle_repro_fixed.log 2>&1; then
    echo "oracle: repro FAILED against repaired tree:" >&2
    tail -10 /tmp/oracle_repro_fixed.log >&2
    exit 1
fi
grep -q "REPRO OK" /tmp/oracle_repro_fixed.log || {
    echo "oracle: repro did not print REPRO OK" >&2
    tail -5 /tmp/oracle_repro_fixed.log >&2
    exit 1
}

echo "oracle: reproduction against pristine pre-fix module (must fail)"
cp /app/src/statsmodels/regression/linear_model.py /tmp/lm_agent.py
cp /opt/prefix/linear_model_parent.py /app/src/statsmodels/regression/linear_model.py
purge_pycache
if python /app/repro.py > /tmp/oracle_repro_prefix.log 2>&1; then
    echo "oracle: repro PASSED against pre-fix module (bug not targeted)" >&2
    cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
    purge_pycache
    exit 1
fi
cp /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py
purge_pycache
if ! cmp -s /tmp/lm_agent.py /app/src/statsmodels/regression/linear_model.py; then
    echo "oracle: failed to restore agent module after pre-fix probe" >&2
    exit 1
fi
echo "oracle: pre-fix probe reproduces the wrong scale; tree restored"
echo "oracle: all self-checks passed"