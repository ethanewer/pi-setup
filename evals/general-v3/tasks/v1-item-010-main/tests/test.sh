#!/bin/bash
mkdir -p /logs/verifier
reward=0

if ! [ -f /app/netlist.c ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

if ! gcc -O2 -o /tmp/netlist_v /app/netlist.c 2>/tmp/compile_err.txt; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

ok=0
selftest_out=$(/tmp/netlist_v 2>/dev/null)
if [ -n "$selftest_out" ] && echo "$selftest_out" | grep -q "SELFTEST_PASS"; then
  if python3 - <<'PYEOF'
import sys, subprocess
def ref_isqrt(n):
    r = 0
    while (r + 1) * (r + 1) <= n:
        r += 1
    return r
def ref_fib(k):
    a, b = 0, 1
    if k == 0:
        return 0
    for _ in range(2, k + 1):
        a, b = b, a + b
    return b
def run(mode, val):
    return int(subprocess.run(['/tmp/netlist_v', mode, str(val)], capture_output=True, text=True).stdout.split()[0])
for n in [0, 4, 9, 16, 100, 255, 1000, 4096, 10000, 65535, 123456, 1000000]:
    if run('isqrt', n) != ref_isqrt(n):
        sys.exit(1)
for k in [0, 1, 2, 5, 10, 20, 29, 30]:
    if run('fib', k) != ref_fib(k):
        sys.exit(1)
sys.exit(0)
PYEOF
then
    ok=1
  fi
fi

reward=$ok
echo "$reward" > /logs/verifier/reward.txt