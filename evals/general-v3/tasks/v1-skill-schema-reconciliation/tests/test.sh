#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, csv

def load_old():
    d = {}
    with open('/app/old.tsv') as f:
        rows = [l.rstrip('\n').split('\t') for l in f]
    for r in rows[1:]:
        if len(r) < 4:
            continue
        cid, name, email, city = [x.strip() for x in r[:4]]
        if cid:
            d[int(cid)] = {'name': name, 'email': email, 'city': city}
    return d

def load_new():
    d = {}
    with open('/app/new.csv', newline='') as f:
        for row in csv.DictReader(f):
            cid = int(row['id'].strip())
            d[cid] = {'name': row['name'].strip(), 'email': row['email'].strip(),
                      'phone': row['phone'].strip(), 'city': row['city'].strip()}
    return d

old = load_old()
new = load_new()
records = []
conflicts = []
for cid in sorted(set(old) | set(new)):
    if cid in new:
        n = new[cid]
        records.append({'id': cid, 'name': n['name'], 'email': n['email'], 'phone': n['phone'], 'city': n['city']})
    else:
        o = old[cid]
        records.append({'id': cid, 'name': o['name'], 'email': o['email'], 'phone': None, 'city': o['city']})
    if cid in old and cid in new:
        for field in ('city', 'email'):
            ov = old[cid][field]
            nv = new[cid][field]
            if ov and nv and ov != nv:
                conflicts.append({'id': cid, 'field': field, 'old': ov, 'new': nv})

got = json.load(open('/app/reconciled.json'))
expected = {'records': records, 'conflicts': conflicts}
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt