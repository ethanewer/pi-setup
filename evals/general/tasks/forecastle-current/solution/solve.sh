#!/bin/bash
# Oracle for forecastle-current: reproduces the bug, proves the reproduction
# is real on the unfixed tree, applies the fix to the library source, then
# proves the reproduction and the project's own suite go green.
# The oracle never reads anything under /tests.
set -euo pipefail

# 1) Deliverable: the reproduction script, contract-compliant.
cp /solution/reproduce.py /app/reproduce.py
chmod +x /app/reproduce.py

# 2) On the pristine (buggy) tree the reproduction must show the bug:
#    exit nonzero and print the BUG marker.
set +e
python3 /app/reproduce.py > /tmp/repro-before.txt 2>&1
before_rc=$?
set -e
if [ "$before_rc" -eq 0 ]; then
    echo "ORACLE ERROR: reproduction exited 0 on the buggy tree" >&2
    cat /tmp/repro-before.txt >&2
    exit 1
fi
grep -q '^BUG' /tmp/repro-before.txt
echo "-- reproduction on unfixed tree (expect BUG): --"
cat /tmp/repro-before.txt

# 3) Apply the fix to the library source under /app/src/httpx.
python3 /solution/client_fix.py

# 4) The reproduction must now honour the timeout: exit 0, OK marker.
python3 /app/reproduce.py | tee /tmp/repro-after.txt
grep -q '^OK' /tmp/repro-after.txt

# 5) The project's own regression test plus the selected timeout tests.
cd /app/src
python3 -m pytest tests/test_timeouts.py -q -p no:cacheprovider -m "not network" -k "read_timeout or pool_timeout or new_request_send_timeout"

# 6) The client suites prove nothing else broke.
python3 -m pytest tests/client/test_client.py tests/client/test_async_client.py -q -p no:cacheprovider -m "not network"

echo "forecastle-current oracle done"