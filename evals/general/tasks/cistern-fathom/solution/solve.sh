#!/bin/bash
# cistern-fathom oracle: apply the genuine upstream one-line fix to
# TypeConversionDict.get -- absorb TypeError from the converter the same way
# ValueErrors are absorbed -- then prove the repro flips from a TypeError to
# the default value -1.
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p = Path("/app/src/src/werkzeug/datastructures/structures.py")
s = p.read_text()
orig = "            except ValueError:\n                rv = default\n"
new = "            except (ValueError, TypeError):\n                rv = default\n"
n = s.count(orig)
assert n == 1, f"anchor for the fix found {n} times, expected exactly 1"
p.write_text(s.replace(orig, new, 1))
print("patched TypeConversionDict.get to absorb (ValueError, TypeError)")
PY
out=$(PYTHONPATH=/app/src/src python3 -c \
  "from werkzeug.datastructures import TypeConversionDict; \
print(TypeConversionDict(baz=None).get('baz', default=-1, type=int))")
[ "$out" = "-1" ] || { echo "oracle repro printed '$out', expected -1" >&2; exit 1; }
echo "repro now prints -1"