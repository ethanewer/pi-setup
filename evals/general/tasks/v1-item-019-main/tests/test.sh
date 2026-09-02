#!/bin/bash
mkdir -p /logs/verifier
reward=0

ok=$(python3 - <<'PYEOF'
import os, json, sqlite3
evidence = '/app/evidence'
out = '/app/recovered'
try:
    wal = open(os.path.join(evidence, 'orders.db-wal'), 'rb').read()
    if os.path.getsize(os.path.join(evidence, 'orders.db-wal')) != 16512:
        print('evidence wal size changed'); raise SystemExit(1)
    key = None
    for cand in range(256):
        dec = [wal[32+i] ^ cand for i in range(4)]
        if dec == [0, 0, 0, 1]:
            key = cand
            break
    if key is None:
        print('could not infer xor key from evidence'); raise SystemExit(1)

    db_path = os.path.join(out, 'orders.db')
    if not os.path.exists(db_path):
        print('recovered db missing'); raise SystemExit(1)
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

reward=$ok
echo "$reward" > /logs/verifier/reward.txt