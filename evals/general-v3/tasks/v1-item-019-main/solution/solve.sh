#!/bin/bash
set -euo pipefail

python3 - <<'PYEOF'
import shutil, os, sqlite3, json

evidence = '/app/evidence'
out = '/app/recovered'
os.makedirs(out, exist_ok=True)

# 1. Work from copies (preserve original evidence).
db_src = os.path.join(evidence, 'orders.db')
wal_src = os.path.join(evidence, 'orders.db-wal')
wal_copy = os.path.join(out, 'orders.db-wal')
shutil.copyfile(db_src, os.path.join(out, 'orders.db'))
shutil.copyfile(wal_src, wal_copy)

data = bytearray(open(wal_src, 'rb').read())

# 2. Infer the single repeating XOR byte.
#    Frame #1 header begins at offset 32; its first 4 bytes (after XOR with
#    the key) must be the big-endian frame number 00 00 00 01.
key = None
for cand in range(256):
    dec = [data[32 + i] ^ cand for i in range(4)]
    if dec == [0, 0, 0, 1]:
        key = cand
        break
assert key is not None, "could not infer XOR key"

# 3. Repair a copy: XOR key over bytes [32, end); header stays intact.
for i in range(32, len(data)):
    data[i] ^= key
open(wal_copy, 'wb').write(data)

# 4. Open the DB next to the repaired WAL -> replay/checkpoint.
conn = sqlite3.connect(os.path.join(out, 'orders.db'))
count = conn.execute('SELECT COUNT(*) FROM orders').fetchone()[0]
integrity = conn.execute('PRAGMA integrity_check').fetchone()[0]
conn.close()
assert count == 140, f"expected 140 rows, got {count}"
assert integrity == 'ok'

report = {'recovered': str(key), 'recovered_rows': count}
with open(os.path.join(out, 'report.json'), 'w') as f:
    json.dump(report, f)
print('recovered rows:', count, 'xor key:', key)
PYEOF