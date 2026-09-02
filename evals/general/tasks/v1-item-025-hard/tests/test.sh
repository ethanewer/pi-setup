#!/bin/bash
# Verifier for item-025 (OCR batch pipeline): objective classification checks.
mkdir -p /logs/verifier

python3 - <<'PY'
import json
import os

EXPECTED = {
    'doc-01.pdf': 'invoices', 'doc-02.pdf': 'receipts', 'doc-03.png': 'invoices',
    'doc-04.png': 'receipts', 'doc-05.pdf': 'invoices', 'doc-06.pdf': 'receipts',
    'doc-07.png': 'receipts', 'doc-08.bin': 'unknown',
}

ROOT = '/app'
inbox = os.path.join(ROOT, 'inbox')
base = os.path.join(ROOT, 'processed')
errs = []

# 1) no input may remain in the inbox
if os.path.isdir(inbox):
    for fn in sorted(os.listdir(inbox)):
        p = os.path.join(inbox, fn)
        if os.path.isfile(p) and fn in EXPECTED:
            errs.append('still in inbox: ' + fn)

# 2) each expected source is in processed/<folder> exactly once
found = {}
for folder in ('invoices', 'receipts', 'unknown'):
    d = os.path.join(base, folder)
    if os.path.isdir(d):
        for fn in os.listdir(d):
            found.setdefault(fn, []).append(folder)

for fn, folder in EXPECTED.items():
    locs = found.get(fn, [])
    if folder in locs and len(locs) == 1:
        continue
    if not locs:
        errs.append('%s not found in any processed folder' % fn)
    else:
        errs.append('%s expected in %s but found in %s' % (fn, folder, sorted(locs)))

# 3) report.json valid and classification matches expected
report = os.path.join(base, 'report.json')
if not os.path.isfile(report):
    errs.append('report.json missing')
else:
    try:
        data = json.load(open(report))
    except Exception as e:
        data = None
        errs.append('report.json invalid: %r' % e)
    if data is not None:
        recs = data.get('records') if isinstance(data, dict) else None
        if not isinstance(recs, list):
            errs.append('no records list in report')
        else:
            got = sorted(r.get('source') for r in recs)
            if got != sorted(EXPECTED):
                errs.append('report sources mismatch: %r != expected' % (got,))
            for r in recs:
                s = r.get('source')
                dest = r.get('destination')
                if dest not in ('invoices', 'receipts', 'unknown'):
                    errs.append('bad destination for %s: %r' % (s, dest))
                if dest != EXPECTED.get(s):
                    errs.append('WRONG CLASS %s -> %s (expected %s)' % (s, dest, EXPECTED.get(s)))
                actual = found.get(s, [])
                if dest in actual and len(actual) == 1:
                    pass
                else:
                    errs.append('report %s dest %s inconsistent with fs %s' % (s, dest, actual))

reward = 1 if not errs else 0
open('/logs/verifier/reward.txt', 'w').write('%d\n' % reward)
for e in errs:
    print('ERR:', e)
PY
exit 0