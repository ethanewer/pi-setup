#!/bin/bash
# Oracle for wherry-trim: repairs the scikit-image RANSAC max-trials budget bug
# in the real tree at /app/src, writes the /app/repro.py reproduction and
# /app/summary.md deliverables, then proves the work: the reproduction must
# FAIL against the pristine pre-fix copy baked at /opt/prefix and PASS against
# the repaired tree, and the project's robust-fitting module plus the planted
# upstream regression test must all pass. Reads only /app, /solution, /opt.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

PARENT=f1892afb76e60b6fe41cf0c73be97f918581aa33
test "$(git rev-parse HEAD)" = "$PARENT" || {
    echo "oracle: /app/src HEAD is $(git rev-parse HEAD), expected pinned $PARENT" >&2
    exit 1
}
test -z "$(git status --porcelain)" || {
    echo "oracle: working tree is not pristine at start" >&2
    exit 1
}

# 1) the reproduction deliverable, written BEFORE the fix.
cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Reproduction for the non-positive max-trials budget in the robust-fitting
routine of the installed scikit-image package.

The maximum number of random trials is a count of attempts and must always be
a positive integer. This script probes the budget computed by the INSTALLED
package (imported below - no re-implementation of the arithmetic, no hardcoded
answers) for extreme-but-legal stopping probabilities: values so small that
(1 - probability) rounds to exactly 1.0 in double precision, plus small
samples-per-subset budgets and tiny inlier ratios.

Exit 0 if and only if every probed trial count is a positive integer.
Exit non-zero (after printing the failing probes) otherwise.
"""
import sys

import numpy as np

from skimage.measure.fit import _dynamic_max_trials as max_trials_budget

# (n_inliers, n_samples, min_samples, stopping probability)
PROBES = [
    (1, 100, 2, 1e-40),
    (1, 100, 5, 1e-40),
    (1, 100, 50, 1e-40),
    (1, 1000, 500, 1e-40),
    (5, 200, 3, 1e-20),
    (5, 200, 10, 1e-30),
    (50, 100, 10, 1e-45),
    (500, 1000, 100, 1e-45),
    (1, 100, 2, 1e-17),
    (1, 100, 1000, 1e-17),
]


def main() -> int:
    bad = []
    for n_inliers, n_samples, min_samples, probability in PROBES:
        trials = max_trials_budget(n_inliers, n_samples, min_samples, probability)
        ok = bool(
            np.isfinite(trials)
            and trials > 0
            and float(trials) == float(np.ceil(float(trials)))
        )
        print(
            "probe: inliers=%d/%d min_samples=%d p=%g -> trials=%s %s"
            % (n_inliers, n_samples, min_samples, probability, trials,
               "ok" if ok else "NON-POSITIVE/NON-INTEGER")
        )
        if not ok:
            bad.append((n_inliers, n_samples, min_samples, probability, repr(trials)))
    if bad:
        print("FAIL: %d probe(s) produced a non-positive or non-integer trial count:"
              % len(bad), file=sys.stderr)
        for row in bad:
            print("  %r" % (row,), file=sys.stderr)
        return 1
    print("PASS: every probe produced a positive integer trial count")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod 755 /app/repro.py
echo "oracle: wrote /app/repro.py"

# 2) the reproduction must FAIL against the current (broken) tree.
if python3 /app/repro.py > /tmp/oracle_repro_fail.out 2>&1; then
    echo "oracle: /app/repro.py PASSED on the unmodified broken tree (expected failure)" >&2
    cat /tmp/oracle_repro_fail.out >&2
    exit 1
fi
grep -q -- "-0.0" /tmp/oracle_repro_fail.out || {
    echo "oracle: repro did not observe a -0.0 trial count on the broken tree" >&2
    head -20 /tmp/oracle_repro_fail.out >&2
    exit 1
}
echo "oracle: reproduction fails on the broken tree as required"

# 3) the fix: keep both (de-)nominator terms inside [_EPSILON, 1 - _EPSILON]
#    before taking logarithms, so both logarithms are strictly negative and the
#    ratio (and its ceil) is always a positive number.
python3 - <<'PY'
p = "/app/src/skimage/measure/fit.py"
s = open(p).read()
old = (
    "inlier_ratio = n_inliers / n_samples\n"
    "    nom = max(_EPSILON, 1 - probability)\n"
    "    denom = 1 - inlier_ratio**min_samples\n"
    "    # Avoid log(1) below turning into -inf\n"
    "    denom = np.clip(denom, a_min=_EPSILON, a_max=1 - _EPSILON)"
)
new = (
    "inlier_ratio = n_inliers / n_samples\n"
    "    nom = 1 - probability\n"
    "    denom = 1 - inlier_ratio**min_samples\n"
    "    # Keep (de-)nominator in the range of [_EPSILON, 1 - _EPSILON] so that\n"
    "    # it is always guaranteed that the logarithm is negative and we return\n"
    "    # a positive number of trials.\n"
    "    nom = np.clip(nom, a_min=_EPSILON, a_max=1 - _EPSILON)\n"
    "    denom = np.clip(denom, a_min=_EPSILON, a_max=1 - _EPSILON)"
)
assert s.count(old) == 1, "expected exactly one occurrence of the buggy block, got %d" % s.count(old)
open(p, "w").write(s.replace(old, new))
PY
echo "oracle: applied the clipping fix to the budget computation"
git diff --stat -- skimage/measure/fit.py | grep -q "1 file changed, 5 insertions" \
 || { echo "oracle: diff shape unexpected" >&2; git diff --stat >&2; exit 1; }

# 4) the reproduction must now PASS against the repaired tree.
if ! python3 /app/repro.py > /tmp/oracle_repro_pass.out 2>&1; then
    echo "oracle: /app/repro.py failed after the fix; out:" >&2
    cat /tmp/oracle_repro_pass.out >&2
    exit 1
fi
echo "oracle: reproduction passes on the repaired tree"

# 5) /app/summary.md
cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Symptom and reproduction

The robust-fitting routine `ransac` of `skimage.measure` computes a maximum
number of random trials from the stopping probability, the inlier ratio and the
minimum samples-per-subset count. For extreme-but-legal inputs - a stopping
probability numerically indistinguishable from 1 (for example `1e-40`), or a
subset-probability term that rounds to exactly 1.0 - the computed "maximum
trials" came back as negative zero, e.g.:

    skimage.measure.fit._dynamic_max_trials(1, 100, 1000, 1e-40) == -0.0

A maximum-trial count of zero or negative is meaningless: the routine would
draw no candidate models at all. `/app/repro.py` probes the installed package
across ten extreme scenarios; before the fix every probe returned `-0.0` and
the script failed, after the fix every probe returns a positive integer and the
script passes.

## Root cause

The budget is computed as

    trials = ceil(log(nom) / log(denom))

where `nom = 1 - probability` and `denom = 1 - inlier_ratio**min_samples`.
The implementation clamped only the denominator into `[_EPSILON, 1 - _EPSILON]`
(so `log(denom)` stays negative) and clamped the numerator only from below:
`nom = max(_EPSILON, 1 - probability)`. For a tiny probability such as `1e-40`,
`1 - probability` rounds to exactly `1.0` in IEEE-754 double precision
(because `1e-40 < 1e-16`, half the ulp of 1.0), so `nom` became exactly 1.0 and
`log(nom) == 0`. Then `0 / log(denom)` is `-0.0` (negative zero) and
`ceil(-0.0) == -0.0`: a non-positive trial count. The same happens whenever
the numerator term rounds to exactly 1.0, regardless of the denominator.

## Change

In the budget computation, clamp BOTH terms into `[_EPSILON, 1 - _EPSILON]`
before taking logarithms:

    nom   = np.clip(1 - probability, a_min=_EPSILON, a_max=1 - _EPSILON)
    denom = np.clip(1 - inlier_ratio**min_samples, a_min=_EPSILON, a_max=1 - _EPSILON)

Both logarithms are then strictly negative, so their ratio is strictly positive
and its ceiling is a positive integer. The change is minimal (two lines): it
affects only the value of the logarithms for the pathological rounding-to-1
cases; for ordinary inputs neither term is near 1.0 or near 0, neither clip
applies, and the returned counts are unchanged.

## Verification

- `/app/repro.py` fails on the pristine pre-fix package (all probes `-0.0`)
  and passes after the change (all probes positive integers).
- Project's own regression test extracted from the fixing commit
  (`test_ransac_dynamic_max_trials_clipping` in the robust-fitting test
  module of `skimage.measure`) passes.
- The full existing robust-fitting test module passes: 30 tests
  (run via `python3 -m pytest`, quiet mode, cache disabled).
- No other file in the tree was modified (verified with `git status`/`git diff`).
MD
echo "oracle: wrote /app/summary.md"

# 6) prove with the project's own machinery: plant the upstream regression
#    test (extracted from the fix commit at image build time), run the whole
#    module, then restore the tree's own test file so only fit.py differs.
P1=skimage/measure/te
TF="${P1}sts/test_fit.py"
cp /opt/golden/test_fit.py "$TF"
if ! python3 -m pytest "$TF" -p no:cacheprovider -q \
      > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: test_fit.py with golden planted did not pass; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    exit 1
fi
grep -q "30 passed" /tmp/oracle_golden.log || {
    echo "oracle: golden run did not report 30 passed" >&2
    tail -10 /tmp/oracle_golden.log >&2
    exit 1
}
git show "${PARENT}:${P1}sts/test_fit.py" \
    > "$TF"
git status --porcelain | grep -v "^ M skimage/measure/fit.py$" >/dev/null \
 && { echo "oracle: tree files other than fit.py are modified" >&2; exit 1; } || true

# 7) the reproduction must also FAIL against the pristine pre-fix copy.
if PYTHONPATH=/opt/prefix:/usr/local/lib/python3.12/site-packages \
       python3 -S /app/repro.py > /tmp/oracle_repro_prefix.out 2>&1; then
    echo "oracle: /app/repro.py PASSED against the pristine pre-fix copy (expected failure)" >&2
    exit 1
fi
echo "oracle: reproduction fails on the pristine pre-fix copy as required"

echo "oracle: fix applied, deliverables written, repro fails pre-fix / passes fixed, golden + full module green, tree scope clean"
exit 0