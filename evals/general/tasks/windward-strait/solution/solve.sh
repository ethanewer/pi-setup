#!/bin/bash
# Oracle for windward-strait: repairs the trust-region iteration loop at its
# root cause, writes the deliverable reproduction and diagnosis, and proves
# the fix with the project's own trust-region test suite.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

python3 /solution/oracle_fix.py || exit 1

cp /solution/oracle_reproduce.py /app/reproduce.py
chmod 644 /app/reproduce.py

cat > /app/diagnosis.md <<'MD'
## Diagnosis: trust-region solvers crash or stall on partially-defined objectives

### Module
`scipy/optimize/_trustregion.py`, function `_minimize_trust_region` -- the
shared iteration loop behind `minimize(method='trust-exact')` and
`minimize(method='trust-ncg')`.

### Root cause
The loop constructed the full local quadratic model at the *proposed* trial
point -- evaluating the objective, the gradient AND the Hessian there --
*before* deciding whether to accept the step. When the objective is only
defined on part of the domain, an out-of-domain proposal makes the Hessian
callback raise, aborting the whole run. A NaN objective at the trial point
was also never treated as a rejection: the acceptance ratio became NaN, every
comparison evaluated false, and the solver repeated the same rejected
proposal until it hit `maxiter` and reported failure, instead of shrinking
the trust radius and recovering.

### Fix
Evaluate the raw objective at the candidate point first and map a NaN value
to +inf so the step is rejected and the trust radius shrinks; build the
local model at the new point only after the step is accepted. This keeps the
Hessian (and gradient) away from out-of-domain points on rejected steps and
lets the search converge to the true minimizer.

### Verification
`/app/reproduce.py` exits 0 and the library's own trust-region solver
test file (9 tests, including the upstream regression test for this bug)
passes from the repaired tree.
MD

# Self-check: the reproduction must pass on the repaired tree now.
python3 /app/reproduce.py > /tmp/oracle_repro.log 2>&1
status=$?
echo "oracle: reproduction exit status: $status"
if [ $status -ne 0 ]; then
    echo "oracle: reproduction still fails after the fix; tail:" >&2
    tail -8 /tmp/oracle_repro.log >&2
fi
exit 0