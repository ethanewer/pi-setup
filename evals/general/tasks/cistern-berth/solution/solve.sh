#!/bin/bash
# Oracle for cistern-berth: applies the upstream-equivalent fix to the real
# checkout at /app/src, proves the observable contract end to end, keeps
# the project's own forwarded suite green, runs the extracted golden
# regression test, then writes the /app/fix-report.md deliverable.
#
# The change is exactly what upstream shipped for aiohttp issue #13229
# (commit b2b2bce in aio-libs/aiohttp): stop the Forwarded parse loop making
# "progress" by jumping to find()'s -1 + 1 == 0 and spinning forever. It
# never reads test fixtures.
set -euo pipefail

# 1) The fix in aiohttp/web_request.py: when no further ';' separator
#    exists, a trailing empty/malformed value ends this field-value -- the
#    parser must break out, not wrap around to position 0.
python3 - <<'PY'
from pathlib import Path

path = Path("/app/src/aiohttp/web_request.py")
source = path.read_text()

old = """                elif not field_value[pos : field_value.find(";", pos)].strip(" \\t"):
                    # Empty value
                    pos = field_value.find(";", pos) + 1"""

new = """                elif (semi := field_value.find(";", pos)) == -1:
                    # No further pair to parse; a trailing empty or malformed
                    # value ends this field-value.
                    break
                elif not field_value[pos:semi].strip(" \\t"):
                    # Empty value
                    pos = semi + 1"""

assert source.count(old) == 1, f"buggy block not found (count={source.count(old)})"
source = source.replace(old, new, 1)
assert "semi :=" in source and "No further pair to parse" in source
path.write_text(source)
print("patched /app/src/aiohttp/web_request.py")
PY

cd /app/src

# 2) The observable contract, in a fresh interpreter: the task reproducer
#    terminates and parses 'Forwarded: ; a' to {}, and the hidden-case
#    inputs terminate with the expected results.
timeout 30 python3 /probes/forwarded_probe.py

# 3) The project's own regression test for this bug: the golden file
#    extracted from the upstream fix commit at image-build time.
python3 -m pytest -q -p no:cacheprovider --rootdir=/app/src \
    "/opt/golden/test_web_request.py::test_single_forwarded_header_trailing_bad_value"

# 4) The project's own forwarded parsing suite stays green.
python3 -m pytest -q -p no:cacheprovider --rootdir=/app/src \
    -p timeout --timeout=120 tests/test_web_request.py -k forwarded

# 5) The deliverable report.
cat > /app/fix-report.md <<'MD'
# Fix report: `Forwarded` header with a trailing empty/malformed element hangs the parse loop

**Where the fault lives:** `/app/src/aiohttp/web_request.py`, in
`BaseRequest.forwarded` — the loop that splits one Forwarded field-value
into its `name=value` pairs. When parsing stops on an empty or malformed
element (`Forwarded: ; a`, or a bare trailing token like `Forwarded: a`),
the fallback branch computed the next position with
`field_value.find(";", pos) + 1`. If there is no further `;` separator,
`find()` returns `-1` and the expression yields `0`, so `pos` wraps back to
the start of the string instead of advancing: the `while 0 <= pos < len(...)`
loop never terminates and spins at 100% CPU forever. Because this property
runs on the event loop, one such request wedges the whole worker.

**The change:** compute the next separator once
(`semi := field_value.find(";", pos)`), and when no separator remains
(`semi == -1`), a trailing empty/malformed value ends the field-value —
`break` out of the loop instead of resetting `pos` to 0. Valid pairs parsed
before the malformed tail are kept; nothing after it is attributed to the
request.

**Verification:**
- the task reproducer (`Forwarded: ; a` via `make_mocked_request`) now
  terminates and prints `{}`;
- `a`, `for=1.2.3.4; a`, `for=1.2.3.4; ;a`, `for=_real;x`,
  `for="a;b"; somebody` all terminate with the expected dicts;
- the upstream regression test for this bug passes (5 cases) and the
  project's own `tests/test_web_request.py -k forwarded` suite stays green.
MD

# 6) Sanity: report and tree state (no fixtures involved).
test -s /app/fix-report.md
grep -q "/app/src/aiohttp/web_request.py" /app/fix-report.md
git status --porcelain --untracked-files=all
echo "cistern-berth oracle done"