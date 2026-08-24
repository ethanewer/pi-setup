#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/out.csv ] && [ -f /app/macro_recipe.txt ]; then
  if python3 - <<'PYEOF'
import re
src = [ln.decode() for ln in open('/app/data.csv', 'rb').read().splitlines()]
out = [ln.decode() for ln in open('/app/out.csv', 'rb').read().splitlines()]
assert len(out) >= 1000000, len(out)
rx = re.compile(r'^\d+,\d{4}-\d{2}-\d{2},-?[\d.]+$')
for ln in out:
    assert rx.match(ln), ln
def transform(ln):
    m = re.match(r'^(\d+),(\d{4})(\d{2})(\d{2}),(-?[\d.]+)$', ln)
    assert m, ln
    return '%s,%s-%s-%s,%s' % (m.group(1), m.group(2), m.group(3), m.group(4), m.group(5))
assert out[0] == transform(src[0]), out[0]
assert out[-1] == transform(src[-1]), out[-1]
recipe = open('/app/macro_recipe.txt').read()
assert len(recipe.strip()) > 0
assert re.search(r'(vim|:g/|:normal|normal|:%s|macro|key)', recipe, re.I)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt