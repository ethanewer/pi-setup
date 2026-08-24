#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
frags = [line.rstrip('\n') for line in open('/app/fragments.txt') if line.strip()]
assert frags
current = frags[0]
rest = frags[1:]
while rest:
    best_ov = -1
    best_idx = -1
    for i, fr in enumerate(rest):
        m = min(len(current), len(fr))
        ov = 0
        for k in range(m, 0, -1):
            if current[-k:] == fr[:k]:
                ov = k
                break
        if ov > best_ov:
            best_ov = ov
            best_idx = i
    current = current + rest[best_idx][best_ov:]
    rest.pop(best_idx)
got = open('/app/original.txt').read()
if got.endswith('\n'):
    got = got[:-1]
assert got == current, (got, current)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt