#!/bin/bash
# Verifier for umber-ridge (executes-deliverable).
#
# Re-runs the deliverable /app/reconcile.py on the visible sources AND on every
# hidden input set, then independently replays the parsing / cell-grid /
# reconciliation checks against a reference model. Reward is 1 only when all
# capabilities + all hidden edge cases hold.
set -u
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import csv
import json
import os
import subprocess
import sys

import numpy as np
import pyarrow.parquet as pq

REGIONS = ["NORTH", "SOUTH", "EAST", "WEST"]
ROWS = {"NORTH": 2, "SOUTH": 3, "EAST": 4, "WEST": 5}
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s <%s>' % (name, detail))


def close(a, b, tol=1e-6):
    try:
        return isinstance(a, (int, float)) and isinstance(b, (int, float)) \
            and abs(float(a) - float(b)) < tol
    except Exception:  # noqa: BLE001
        return False


def reference(srcdir):
    """Independent model of the contract for a sources dir."""
    rows = []
    for rec in json.load(open(os.path.join(srcdir, 'clients.json')))['records']:
        rows.append((int(rec['client_id']),
                     (rec['first_name'] + ' ' + rec['last_name']).strip(),
                     str(rec['branch']), float(rec['vp_balance'])))
    with open(os.path.join(srcdir, 'deals.csv'), newline='') as fh:
        for line in csv.reader(fh):
            if not line or not line[0].strip() or line[0].strip() == 'deals_id':
                continue
            did, holder, terr, cap = [c.strip() for c in line]
            rows.append((int(did), holder, terr, float(cap)))
    for rec in pq.read_table(os.path.join(srcdir, 'ledger.parquet')).to_pylist():
        rows.append((int(rec['cid']), str(rec['label']), str(rec['zone']),
                     float(rec['val'])))
    gt = json.load(open(os.path.join(srcdir, 'region_report.json')))['grand_totals']
    sums = {r: round(sum(b for _c, _n, rr, b in rows if rr == r), 2)
            for r in REGIONS if r in gt}
    # only canonical regions are grouped
    sums = {r: sums.get(r, 0.0) for r in REGIONS}
    anoms = [r for r in REGIONS if abs(sums[r] - gt[r]) > 1e-6]
    anom = anoms[0] if len(anoms) == 1 else None
    return rows, sums, gt, anom


def check_case(label, srcdir, outdir):
    rows, sums, gt, anom = reference(srcdir)
    if anom is None:
        check(label + '_single_anomaly', False, 'did not detect exactly one')
        return
    r = subprocess.run(['python3', '/app/reconcile.py', srcdir, outdir],
                       capture_output=True, text=True)
    check(label + '_run_exit0', r.returncode == 0, r.stderr[-400:])

    mp = os.path.join(outdir, 'mart.npy')
    if not os.path.exists(mp):
        check(label + '_mart_exists', False, mp)
        return
    m = np.load(mp)
    check(label + '_mart_dtype',
          tuple(m.dtype.names or ()) == ('client_id', 'name', 'region',
                                         'balance_value'),
          m.dtype)
    ref_map = {c: (n, reg, b) for c, n, reg, b in rows}
    got_ids = set(int(x) for x in m['client_id'].tolist())
    check(label + '_mart_client_ids', got_ids == set(ref_map),
          sorted((got_ids ^ set(ref_map))))
    ok = True
    for i in range(m.size):
        cid = int(m['client_id'][i])
        if cid not in ref_map:
            ok = False
            continue
        rn, rreg, rbal = ref_map[cid]
        if str(m['name'][i]) != rn or str(m['region'][i]) != rreg \
                or not close(float(m['balance_value'][i]), rbal):
            ok = False
    check(label + '_mart_rows_ok', ok)

    sp = os.path.join(outdir, 'sheet.jsonl')
    if not os.path.exists(sp):
        check(label + '_sheet_exists', False, sp)
        return
    grid = {}
    for line in open(sp):
        op = json.loads(line)
        grid[op['cell']] = op['value']
    for region in REGIONS:
        row = ROWS[region]
        check(label + '_A%d' % row, grid.get('A%d' % row) == region,
              grid.get('A%d' % row))
        check(label + '_B%d' % row, close(grid.get('B%d' % row), sums[region]),
              grid.get('B%d' % row))
        check(label + '_C%d' % row, close(grid.get('C%d' % row), gt[region]),
              grid.get('C%d' % row))
        flag = grid.get('D%d' % row)
        exp = 'MISMATCH' if region == anom else 'OK'
        check(label + '_D%d' % row, flag == exp, (flag, exp))
    check(label + '_F2', close(grid.get('F2'), gt[anom]), grid.get('F2'))


# visible deliverable produced at /app by the agent's run on /app/sources
check_case('visible', '/app/sources', '/app')
# The declared data deliverables must exist at their literal /app paths
# (visible run writes them to /app because OUT_DIR == /app).
for _lit in ('/app/mart.npy', '/app/sheet.jsonl'):
    check('lit_path_' + os.path.basename(_lit), os.path.exists(_lit), _lit)
for case in ['low-cost', 'sparse', 'stray']:
    check_case(case, '/tests/hidden/' + case, '/tmp/out_' + case)

if probs:
    for p in probs:
        print('FAIL:', p)
    sys.exit(1)
print('ALL_VERIFIER_GATES_OK')
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt