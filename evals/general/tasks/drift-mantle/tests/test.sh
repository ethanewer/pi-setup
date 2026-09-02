#!/bin/bash
# drift-mantle verifier.
# Requires /app/solve.py (general solver) to already exist, plus the visible
# deliverables /app/report.txt /app/value.txt /app/result.csv /app/result.txt
# /app/out.jpg produced from the visible fixture by running the solver.
# Runs the solver on every hidden case under /tests/hidden and validates each
# output byte-for-byte/schema against the expected.json in that case dir.
set -eu
R=/logs/verifier/reward.txt
mkdir -p /logs/verifier
fail() { echo "VERIFIER FAIL: $1" >&2; echo 0 > "$R"; exit 0; }

# --- 1. deliverables exist and are executable -------------------------------
for f in /app/solve.py /app/report.txt /app/value.txt /app/result.csv /app/result.txt /app/out.jpg; do
  [ -f "$f" ] || fail "missing deliverable $f"
done
[ -x /app/solve.py ] || fail "/app/solve.py is not executable"

# --- 2. structural checks on the visible deliverables ------------------------
python3 - <<'PY' || fail "visible deliverable structure"
import re, csv
from PIL import Image
# value.txt : only a float-parseable value
v = open('/app/value.txt').read()
if v.count('\n') > 1: raise SystemExit("value.txt has stray lines")
try:
    float(v.strip())
except Exception:
    raise SystemExit("value.txt not float-parseable: %r" % v)
# result.csv : exact header + string rows
rows = list(csv.reader(open('/app/result.csv', newline='')))
if rows[0] != ['ip', 'count', 'risk']:
    raise SystemExit("result.csv header wrong: %r" % rows[0])
for row in rows[1:]:
    if len(row) != 3 or not re.fullmatch(r'\d+', row[1]) or not re.fullmatch(r'\d+', row[2]):
        raise SystemExit("result.csv row wrong: %r" % row)
# result.txt : label-per-line
for ln in open('/app/result.txt'):
    ln = ln.rstrip('\n')
    if not re.fullmatch(r'[0-9.]+ name=\S+ count=\d+ risk=\d+', ln):
        raise SystemExit("result.txt bad line: %r" % ln)
# report.txt : required headline keys present once each
rep = open('/app/report.txt').read()
for key in ('FILE:', 'LINES:', 'IPS:', 'HITS:', 'FLAG:', 'VERDICT:', 'OBJ:', 'RESULT:'):
    if rep.count(key) == 0:
        raise SystemExit("report.txt missing %s" % key)
    if rep.count(key) > 1:
        raise SystemExit("report.txt has duplicate %s" % key)
# out.jpg : genuine 640x480 JPEG
im = Image.open('/app/out.jpg'); im.load()
if im.format != 'JPEG' or im.size != (640, 480):
    raise SystemExit("out.jpg not a 640x480 JPEG: %r %r" % (im.format, im.size))
# result.txt and result.csv row counts agree
if len(rows) - 1 != sum(1 for _ in open('/app/result.txt')):
    raise SystemExit("result.txt / result.csv row count mismatch")
PY

# --- 3. hidden cases ----------------------------------------------------------
for case in visible a b c; do
  CASEDIR="/tests/hidden/$case"
  if [ "$case" = visible ]; then
    CASELOG="/app/access.log"   # visible fixture shipped in the image
  else
    CASELOG="$CASEDIR/log"
    [ -f "$CASELOG" ] || fail "case $case missing log"
  fi
  [ -f "$CASEDIR/expected.json" ] || fail "case $case missing expected.json"
  OUT="/tmp/out_$case"
  rm -rf "$OUT"; mkdir -p "$OUT"
  python3 /app/solve.py "$CASELOG" "$OUT" >/dev/null 2>&1 \
      || fail "solve.py did not exit 0 on case $case"
  OUT="$OUT" CASE="$case" CASEDIR="$CASEDIR" python3 - <<'PY' || fail "case $case mismatch"
import os, sys, json, csv, re
from PIL import Image
out = os.environ['OUT']; casename = os.environ['CASE']; casedir = os.environ['CASEDIR']
e = json.load(open(os.path.join(casedir, 'expected.json')))

# value.txt
v = open(os.path.join(out, 'value.txt')).read().strip()
if v != str(e['total_hits']):
    raise SystemExit("value.txt %r != %r" % (v, e['total_hits']))

# report.txt headline + top-10 table
rep = open(os.path.join(out, 'report.txt')).read()
def getval(k):
    m = re.search(r'^%s: (.+)$' % re.escape(k), rep, re.M)
    return m.group(1).strip() if m else None
if int(getval('LINES')) != e['total_lines']:
    raise SystemExit("LINES %r" % getval('LINES'))
if int(getval('IPS')) != e['distinct']:
    raise SystemExit("IPS %r" % getval('IPS'))
if int(getval('HITS')) != e['total_hits']:
    raise SystemExit("HITS %r" % getval('HITS'))
if getval('FLAG') != e['flag']:
    raise SystemExit("FLAG %r" % getval('FLAG'))
if getval('VERDICT') != e['verdict']:
    raise SystemExit("VERDICT %r" % getval('VERDICT'))
b = e.get('busiest')
if b is None and e.get('busiest_ip') is not None:
    b = {'ip': e['busiest_ip'], 'count': e['busiest_count'], 'risk': e['busiest_risk']}
if b:
    if getval('OBJ') != b['ip']:
        raise SystemExit("OBJ %r" % getval('OBJ'))
    if getval('RESULT') != '%s:%d:%d' % (b['ip'], b['count'], b['risk']):
        raise SystemExit("RESULT %r" % getval('RESULT'))
else:
    if getval('OBJ') != '-' or getval('RESULT') != '-':
        raise SystemExit("no-busiest OBJ/RESULT wrong")
for i, row in enumerate(e['rows'][:10], 1):
    pat = r'^%4d  %-12s  %5d  %4d$' % (i, row['ip'], row['count'], row['risk'])
    if not re.search(pat, rep, re.M):
        raise SystemExit("report table row %d missing/mismatched" % i)

# result.csv : exact columns/order, all rows as strings
rows = list(csv.reader(open(os.path.join(out, 'result.csv'), newline='')))
if rows[0] != ['ip', 'count', 'risk']:
    raise SystemExit("csv header %r" % rows[0])
got = [(a, int(b), int(c)) for a, b, c in rows[1:]]
exp = [(x['ip'], x['count'], x['risk']) for x in e['rows']]
if got != exp:
    raise SystemExit("csv rows mismatch")

# result.txt : label-per-line, one per distinct row, in sorted order
lines = [ln.rstrip('\n') for ln in open(os.path.join(out, 'result.txt'))]
exp_lines = ["%s name=%s count=%d risk=%d" % (x['ip'], e['basename'], x['count'], x['risk'])
             for x in e['rows']]
if lines != exp_lines:
    raise SystemExit("result.txt lines mismatch (%d vs %d)" % (len(lines), len(exp_lines)))

# out.jpg : JPEG with expected size
im = Image.open(os.path.join(out, 'out.jpg')); im.load()
if im.format != 'JPEG' or im.size != (e['jpg_w'], e['jpg_h']):
    raise SystemExit("out.jpg dims %r %r" % (im.format, im.size))
PY
done

# all good
echo "VERIFIER PASS" >&2
echo 1 > "$R"
exit 0
