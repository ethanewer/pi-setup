#!/bin/bash
# Verifier for sable-mesa: requires the authored deliverables
# (/app/pkg/pyproject.toml, /app/pkg/dotkit/__init__.py), installs the package
# offline into a scratch target, and EXECUTES the installed API (dotkit.dot,
# from dotkit import dot, dotkit.core.dot) on the visible case and every hidden
# case in /tests/hidden. Writes 0/1 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

fail=0
[ -f /app/pkg/pyproject.toml ] || { echo "FAIL: missing /app/pkg/pyproject.toml" >&2; fail=1; }
[ -f /app/pkg/dotkit/__init__.py ] || { echo "FAIL: missing /app/pkg/dotkit/__init__.py" >&2; fail=1; }

SITE=/tmp/dk_site
if [ "$fail" -eq 0 ]; then
    rm -rf "$SITE"
    if ! python3 -m pip install --quiet --no-index --no-deps --no-build-isolation \
            --target "$SITE" /app/pkg > /tmp/dk_install.log 2>&1; then
        echo "FAIL: offline pip install of /app/pkg failed" >&2
        cat /tmp/dk_install.log >&2
        fail=1
    fi
fi

if [ "$fail" -eq 0 ]; then
    if PYTHONPATH="$SITE" python3 /tests/checker.py \
            /tests/case_visible.json /tests/expected_visible.json /tests/hidden; then
        :
    else
        fail=1
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
