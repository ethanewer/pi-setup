#!/bin/bash
# thole-ground oracle: (1) deliver the reproduction script, (2) repair the
# library with the complete FloatConverter.to_url override, (3) prove the fix
# with the reproduction on the required values, the project's own golden test,
# and the full upstream suite. Never reads /tests.
set -eu

# ---- 1. deliverable ----
cp /solution/reproduce.py /app/reproduce.py
chmod +x /app/reproduce.py
echo "deliverable /app/reproduce.py written"

# ---- 2. fix the library ----
python3 /solution/fix_float_url_to_url.py

# ---- 3. prove it ----
echo "--- reproduction on the required values ---"
for v in 0.00001 1e20 2.5e-07 5.0 0.5 1000.0; do
    python3 /app/reproduce.py "$v" | sed 's/^/    /'
done

echo "--- golden test (project's own regression test) ---"
cd /app/src
python3 -m pytest /opt/golden/test_float_no_scientific.py -q -p no:cacheprovider 2>&1 | tail -n 2

echo "--- full upstream suite ---"
python3 -m pytest -q -p no:cacheprovider 2>&1 | tail -n 2

echo "oracle done"