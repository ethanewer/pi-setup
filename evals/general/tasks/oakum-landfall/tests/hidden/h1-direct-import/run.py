#!/usr/bin/env python3
"""Hidden case h1 (direct name normalisation).

Exercises the same distribution-name-normalisation code path the upstream
regression tests cover, from inputs they do NOT use: mixed upper case and
dots, runs of separators, and multiple dot-separated components. The
distribution component produced for each name must equal the canonical
normalised form. Fails at the pre-fix tree (names kept verbatim), passes
once the installed setuptools canonicalises.
"""

from setuptools._normalization import safer_name

CASES = {
    "Camel.Case": "camel_case",
    "x.y.z": "x_y_z",
    "UPPER.Name": "upper_name",
    "a.b-c_d": "a_b_c_d",
    "alpha.beta--Gamma": "alpha_beta_gamma",
}

failures = []
for name, expected in CASES.items():
    got = safer_name(name)
    if got != expected:
        failures.append(f"{name!r}: got {got!r}, expected {expected!r}")

if failures:
    for f in failures:
        print("FAIL:", f)
    raise SystemExit(1)

print("ok: all", len(CASES), "distribution names canonicalised")