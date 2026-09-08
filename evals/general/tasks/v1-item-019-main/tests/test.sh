#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0

ok=$(python3 - <<'PYEOF'
import os, json, sqlite3, sys
evidence = '/app/evidence'
out = '/app/recovered'
try:
    wal = open(os.path.join(evidence, 'orders.db-wal'), 'rb').read()
    if os.path.getsize(os.path.join(evidence, 'orders.db-wal')) != 16512:
        print('evidence wal size changed', file=sys.stderr); print(0); raise SystemExit(1)
    key = None
    for cand in range(256):
        dec = [wal[32+i] ^ cand for i in range(4)]
        if dec == [0, 0, 0, 1]:
            key = cand
            break
    if key is None:
        print('could not infer xor key from evidence', file=sys.stderr); print(0); raise SystemExit(1)

    db_path = os.path.join(out, 'orders.db')
    if not os.path.exists(db_path):
        print('recovered db missing', file=sys.stderr); print(0); raise SystemExit(1)
    con = sqlite3.connect(db_path)
    cur = con.cursor()
    integrity = cur.execute('PRAGMA integrity_check').fetchone()[0]
    count = cur.execute('SELECT COUNT(*) FROM orders').fetchone()[0]
    d1 = cur.execute("SELECT patient,status FROM orders WHERE id=1").fetchone()
    d101 = cur.execute("SELECT patient,status FROM orders WHERE id=101").fetchone()
    d140 = cur.execute("SELECT patient,status FROM orders WHERE id=140").fetchone()
    con.close()
    assert integrity == 'ok', integrity
    assert count == 140, count
    assert d1 == ('Ethan Coleman', 'done'), d1
    assert d101 == ('Marek Nowak', 'booked'), d101
    assert d140 == ('Sana Khalid', 'booked'), d140

    report = json.load(open(os.path.join(out, 'report.json')))
    assert report.get('recovered_rows') == 140, report
    print(1)
except Exception as e:
    print('0')
PYEOF
)

# Only 0 or 1 may reach the reward file. The heredoc's stdout is captured whole,
# so any path that prints a diagnostic instead of a verdict used to write that
# diagnostic as the reward -- this verifier shipped "recovered db missing" into
# reward.txt, which is neither binary nor parseable. Keep the text as a diagnostic
# on stderr and score 0.
case "$ok" in
  0|1) reward=$ok ;;
  *)   [ -n "$ok" ] && echo "verifier printed a non-binary verdict: $ok" >&2
       reward=0 ;;
esac
echo "$reward" > /logs/verifier/reward.txt