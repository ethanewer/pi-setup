#!/bin/bash
mkdir -p /logs/verifier

reward=0
rm -rf /tmp/gdbtest && mkdir -p /tmp/gdbtest
cp /app/debug.c /tmp/gdbtest/
(
  cd /tmp/gdbtest
  gcc -O0 debug.c -o dbg.bin 2>/dev/null
  ./dbg.bin > hid.txt 2>&1
)

if [ -f /app/debugged.json ] && [ -f /tmp/gdbtest/hid.txt ]; then
  if python3 - <<'EOF'
import re, json
text = open('/tmp/gdbtest/hid.txt').read()
m = re.search(r'hid=(-?[0-9]+)', text)
assert m, ('could not parse hid', text)
expected = int(m.group(1))

out = json.load(open('/app/debugged.json'))
assert out['checksum'] == expected, (out, expected)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt