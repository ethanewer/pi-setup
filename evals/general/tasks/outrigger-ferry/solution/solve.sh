#!/bin/bash
# Oracle for outrigger-ferry: applies the two-line upstream fix to the real
# python-poetry/poetry tree at /app/src (wrap a plain-str config setting
# value in a list before iterating, so the remediation pip command renders
# one whole-value --config-settings flag instead of one per character),
# writes the two declared deliverables /app/repro.py and /app/summary.md,
# and proves the work: the reproduction must PASS on the repaired tree and
# FAIL against the pristine pre-fix copy baked at /opt/pre-fix-poetry when
# run under PYTHONPATH, and the project's own regression test for this bug
# (the fix-commit version of tests/installation/test_executor.py, kept out
# of the tree at /opt/golden) must PASS on the repaired tree.
set -u
SRC=/app/src
PY=/opt/poetry-venv/bin/python

cd "$SRC" || { echo "oracle: /app/src missing" >&2; exit 1; }

# ---- apply the upstream fix to the working tree -----------------------------
"$PY" - <<'PY'
from pathlib import Path
p = Path('/app/src/src/poetry/installation/executor.py')
s = p.read_text()
a = "for setting in config_settings:\n                                for setting_value in config_settings[setting]:"
b = "for setting in config_settings:\n                                values = config_settings[setting]\n                                if isinstance(values, str):\n                                    values = [values]\n                                for setting_value in values:"
assert a in s, "anchor line not found in executor.py"
p.write_text(s.replace(a, b))
print("oracle: applied the string-wrap fix to executor.py")
PY

# ---- declared deliverables --------------------------------------------------
cp /solution/repro.py /app/repro.py
chmod +x /app/repro.py

cat > /app/summary.md <<'MD'
# outrigger-ferry fix summary

## Symptom
When an install fails during the build step, poetry prints a remediation
command (`pip wheel --no-cache-dir --use-pep517 ...`). For a package whose
`installer.build-config-settings` contain a plain-string value (for example
an environment-variable-style setting `"CC": "gcc"`), the printed command
was garbled: the string was iterated per character, producing a run of
nonsense options like `--config-settings='CC=g' --config-settings='CC=c'
--config-settings='CC=c'` instead of one `--config-settings='CC=gcc'`
flag. Users could not copy the shown command to retry the build.
List-valued settings rendered one flag per item and were unaffected; only
plain-string values were mangled.

## Root cause
In the Executor's error-path pip-command construction, the loop over a
package's build config settings iterated the setting's value directly:

    for setting in config_settings:
        for setting_value in config_settings[setting]:
            pip_command += f" --config-settings='{setting}={setting_value}'"

A plain `str` value is an iterable of its characters, so a string value
was split into per-character flags. Lists (the documented array form)
behaved correctly per item.

## Change
Wrap a plain `str` value in a one-element list before iterating, so every
setting renders exactly one `--config-settings='K=V'` flag regardless of
whether the configured value is a string or a list:

    for setting in config_settings:
        values = config_settings[setting]
        if isinstance(values, str):
            values = [values]
        for setting_value in values:
            pip_command += f" --config-settings='{setting}={setting_value}'"

## Verification
- /app/repro.py fails on the unmodified tree (per-character garbage, exit
  non-zero) and passes on the repaired tree (whole-string flag, exit 0).
- The project's own regression test for this bug (fix-era
  test_build_backend_error_includes_config_settings_in_pip_command from
  tests/installation/test_executor.py, taken from the fix commit) passes.
- The previously-existing test files pass unchanged.
MD

# ---- prove both directions --------------------------------------------------
if ! "$PY" /app/repro.py > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: repro FAILED on the repaired tree; tail:" >&2
    tail -10 /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
grep -qF -- "--config-settings='CC=gcc'" /tmp/oracle_repro_fixed.out || {
    echo "oracle: repro did not print the whole-string flag on the repaired tree" >&2
    exit 1
}
PYTHONPATH=/opt/pre-fix-poetry "$PY" /app/repro.py > /tmp/oracle_repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "oracle: repro unexpectedly PASSED against the pristine pre-fix copy" >&2
    head -10 /tmp/oracle_repro_prefix.out >&2
    exit 1
fi
grep -q -- "--config-settings='CC=g'" /tmp/oracle_repro_prefix.out || {
    echo "oracle: pre-fix failure was not the per-character garbling symptom" >&2
    head -10 /tmp/oracle_repro_prefix.out >&2
    exit 1
}
echo "oracle: repro FAILS on the pre-fix copy and PASSES on the repaired tree"

# ---- the project's own regression test (pinned golden bytes) ----------------
cp /opt/golden/test_executor.py tests/installation/test_executor.py
if ! /opt/poetry-venv/bin/pytest tests/installation/test_executor.py \
     -k test_build_backend_error_includes_config_settings_in_pip_command \
     --no-header -p no:randomly -o addopts="" > /tmp/oracle_golden.log 2>&1; then
    echo "oracle: golden regression test failed on the repaired tree; tail:" >&2
    tail -20 /tmp/oracle_golden.log >&2
    git checkout -q -- tests/installation/test_executor.py
    exit 1
fi
grep -q "1 passed" /tmp/oracle_golden.log || {
    echo "oracle: golden test did not report 1 passed" >&2
    tail -5 /tmp/oracle_golden.log >&2
    exit 1
}
git checkout -q -- tests/installation/test_executor.py
echo "oracle: the project's own regression test passes on the repaired tree"
echo "oracle: DONE"
exit 0