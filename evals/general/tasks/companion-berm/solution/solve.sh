#!/bin/bash
# Oracle for companion-berm: repairs the real poetry checkout at /app/src by
# applying the upstream fix to Indicator.context() (wrap the yield in
# try/finally so the label is also cleared when the body raises), writes the
# required reproduction deliverable, and demonstrates that both the
# reproduction and the upstream regression test now pass.
set -e

PY=/opt/poetry-venv/bin/python
SRC=/app/src

python3 /solution/fix_provider.py "$SRC/src/poetry/puzzle/provider.py"

# ---- write the reproduction deliverable -----------------------------------
cat > /app/reproduce_indicator_leak.py <<'PY'
#!/opt/poetry-venv/bin/python
"""Reproduce the stale progress-indicator label leak in poetry's resolver.

Enters the resolver's Indicator.context(), sets an activity label, aborts the
operation with an exception inside the block, then checks that the label was
cleaned up and did not leak to code outside the block. Exits 0 iff no stale
label leaks; exits nonzero while the bug is present.
"""
import sys

from poetry.puzzle.provider import Indicator


def main() -> int:
    try:
        with Indicator.context() as set_context:
            set_context("downloading something")
            assert Indicator.CONTEXT == "downloading something"
            raise RuntimeError("network error")
    except RuntimeError:
        pass

    if Indicator.CONTEXT is None:
        print("OK: the aborted operation's label was cleaned up; nothing leaked.")
        return 0
    print(f"BUG PRESENT: stale label leaked out of the aborted block -> {Indicator.CONTEXT!r}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/reproduce_indicator_leak.py

echo "== reproduction deliverable (must pass now the fix is applied) =="
(cd /app && "$PY" reproduce_indicator_leak.py)

echo "== upstream regression test (extracted into /opt/golden) =="
rm -rf /tmp/golden_run && mkdir -p /tmp/golden_run
cp /opt/golden/test_indicator_context_resets_on_exception.py /tmp/golden_run/
(cd "$SRC" && "$PY" -m pytest /tmp/golden_run/test_indicator_context_resets_on_exception.py -q -p no:randomly -o addopts="")
