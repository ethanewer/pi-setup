#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import re
lines = [l.rstrip('\n') for l in open('/app/data.txt') if l.strip()]
rx = re.compile(r'^(\w+) (\w+) (\d{4})$')
expected = []
for ln in lines:
    m = rx.match(ln)
    assert m, ln
    expected.append('%s %s born %s' % (m.group(2), m.group(1), m.group(3)))
got = [l.rstrip('\n') for l in open('/app/result.txt') if l != '\n']
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt