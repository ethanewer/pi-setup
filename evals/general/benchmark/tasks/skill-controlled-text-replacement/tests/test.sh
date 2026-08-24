#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/out.txt ]; then
  if python3 - <<'PYEOF'
import re
def go(ln):
    if 'LOCK:ON' in ln:
        return ln
    return re.sub(r'\bTODO\b', 'DONE', ln)
with open('/app/spec.txt') as f:
    spec = f.read().splitlines()
if not [l for l in spec if 'TODO' in l]:
    # nothing to transform; still valid if outputs identical
    pass
with open('/app/out.txt') as f:
    got = f.read().splitlines()
assert len(got) == len(spec), (len(got), len(spec))
for s, g in zip(spec, got):
    assert go(s).rstrip() == g.rstrip(), (s, g)
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt