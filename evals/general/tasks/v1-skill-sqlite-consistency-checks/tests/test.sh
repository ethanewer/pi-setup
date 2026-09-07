#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/integrity.txt ] && [ -f /app/fks.txt ]; then
  python3 - <<'PY' && reward=1
import sqlite3

con = sqlite3.connect('/app/data.db')

exp_int = [str(r[0]) for r in con.execute('PRAGMA integrity_check')]
got_int = [ln.strip() for ln in open('/app/integrity.txt') if ln.strip()]
assert got_int == exp_int, (got_int, exp_int)

exp_fk = [f"{r[0]}\t{r[1]}\t{r[2]}" for r in con.execute('PRAGMA foreign_key_check')]
lines = open('/app/fks.txt').read().splitlines()
got_fk = [ln.rstrip('\r\n').strip('\n') for ln in lines]
# normalize empty trailing line
while got_fk and got_fk[-1] == '':
    got_fk.pop()
while exp_fk and exp_fk[-1] == '':
    exp_fk.pop()
assert got_fk == exp_fk, (got_fk, exp_fk)
assert exp_fk, "expected at least one FK violation in this seeded database"
PY
fi
echo "$reward" > /logs/verifier/reward.txt