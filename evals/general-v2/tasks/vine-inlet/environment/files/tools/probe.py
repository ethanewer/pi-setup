#!/usr/bin/env python3
"""probe.py -- validate an observation table using the hedge venv.

Reads a comma-separated table via lotusfields and prints a stable one-line JSON
result. It ALSO imports coreclutch, so that second frozen top-level package must
stay importable. Run from the hedge venv:
    /app/env/.venv/bin/python /app/tools/probe.py <table>
The dtype_backend="tight" keyword below does not exist in the OLD lotusfields
release bundled in the broken venv -- that call raises TypeError until the
environment is upgraded to lotusfields 0.9.0.
"""
import json
import os
import sys

import coreclutch          # noqa: F401  (must stay importable)
from lotusfields import LotusInputError, read_table


def emit(obj, code):
    print(json.dumps(obj, separators=(",", ":")), flush=True)
    sys.exit(code)


def main():
    if len(sys.argv) != 2:
        emit({"error": "usage", "code": 400, "hint": "probe.py <path>"}, 2)
    path = sys.argv[1]
    if not os.path.exists(path):
        emit({"error": "not-found", "code": 404}, 3)
    try:
        rows = read_table(path, dtype_backend="tight")
    except LotusInputError as exc:
        msg = str(exc)
        if msg.startswith("missing-columns:"):
            emit({"error": msg, "code": 422}, 4)
        if msg.startswith("non-numeric-flux:"):
            emit({"error": msg, "code": 422}, 4)
        if msg == "empty-data":
            emit({"error": msg, "code": 422}, 4)
        emit({"error": "unhandled", "detail": msg, "code": 500}, 5)
    except Exception as exc:              # OLD lotus raises TypeError here
        if type(exc).__name__ == "TypeError":
            emit({"error": "outdated-library", "code": 500}, 5)
        emit({"error": "read-failure", "detail": str(exc), "code": 500}, 5)

    total_flux = round(sum(float(r["flux"]) for r in rows), 3)
    zones = sorted(set(r["zone"] for r in rows))
    emit({"ok": True, "rows": len(rows),
          "total_flux": total_flux, "zones": zones}, 0)


main()
