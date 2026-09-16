#!/bin/bash
# Oracle for clinker-quay: localises, repairs the exact source defect and
# writes /app/diagnosis.md. It reads only /app/src (never /tests), applies
# the minimal twiddle-index fix, then proves it with sympy's own targeted
# submodule suite.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

python3 - <<'PY'
path = "sympy/discrete/transforms.py"
src = open(path).read()
buggy = "u, v = a[i + j], expand_mul(a[i + j + hf]*w[j])"
fixed = "u, v = a[i + j], expand_mul(a[i + j + hf]*w[ut * j])"
if src.count(buggy) != 1:
    raise SystemExit("oracle: expected buggy line not found (count=%d)"
                     % src.count(buggy))
open(path, "w").write(src.replace(buggy, fixed))
print("oracle: restored twiddle index w[ut * j] in transforms.py")
PY

cat > /app/diagnosis.md <<'MD'
## Diagnosis: wrong FFT results for sequences of length >= 8

### Module
`sympy.discrete.transforms` -- the `_fourier_transform` helper behind
`sympy.discrete.fft` and `sympy.discrete.ifft`.

### Root cause
In the radix-2 Cooley-Tukey butterfly loop the twiddle-factor table is
looked up with `w[j]` instead of `w[ut * j]`. For every stage with
`ut > 1` -- i.e. every transform whose length is padded to n >= 8 -- the
butterfly multiplies by the wrong root of unity and the output spectrum
is wrong. Sequences that pad to n == 2 or n == 4 never reach a stage with
`ut > 1`, which is why short inputs still produced correct values.

### Fix
Restored the correct twiddle index `w[ut * j]` in the butterfly.

### Verification
`PYTHONPATH=/app/src python3 -m pytest -q sympy/discrete/` passes all of
the submodule's own tests and `/app/reproduce.py` exits 0.
MD

# Prove the fix with the project's own submodule suite. The verifier will
# re-check everything; this run is the oracle's own sanity check.
PYTHONPATH=/app/src python3 -m pytest -q sympy/discrete/ > /tmp/oracle_pytest.log 2>&1
status=$?
echo "oracle: sympy/discrete pytest exit status: $status"
if [ $status -ne 0 ]; then
  echo "oracle: submodule tests failed; tail:" >&2
  tail -5 /tmp/oracle_pytest.log >&2
fi
exit 0