#!/bin/bash
# Verifier for juniper-bridge (executes-deliverable). Re-runs /app/solve.py on
# the visible scenario and on every hidden case, and checks every deliverable:
# digit grid, secret word, transcribed-code value, recovered print-path word,
# reconstructed shapes, the three fit inlier counts, and that the two raster
# renders and the recovered print-path are read by OCR as expected.
# Writes reward to /logs/verifier/reward.txt (1 all pass, 0 otherwise).
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import os, json, re, shutil, subprocess, sys

SOL = "/app/solve.py"
failures = []

def fail(msg):
    failures.append(msg)

def check(c, m):
    if not c:
        fail(m)

check(os.path.exists(SOL), "missing deliverable /app/solve.py")

# Every listed deliverable must be checked. /app/answer.json is the required
# output of running /app/solve.py on the shipped scenario: the instruction
# explicitly demands it exist, and solve.sh produces it. The verifier must
# confirm existence and (for the visible scenario) correct content.
check(os.path.exists("/app/answer.json"), "missing deliverable /app/answer.json")


def normalize(t):
    return re.sub(r'[^A-Z0-9]+', '', (t or '').upper())

def ocr_file(path, psm='6'):
    r = subprocess.run(['tesseract', path, '-', '--psm', psm],
                       capture_output=True, text=True)
    return r.stdout

def canon(shapes):
    items = []
    for s in shapes or []:
        if s.get('t') == 'poly':
            pts = tuple(sorted(tuple(map(int, p)) for p in (s.get('pts') or [])))
            items.append(('poly', pts))
        else:
            key = tuple(sorted((k, int(s[k])) for k in s if k != 't'))
            items.append((s.get('t'), key))
    return sorted(items)

def run_scenario(inp_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    r = subprocess.run(['python3', SOL, inp_dir, out_dir],
                       capture_output=True, text=True)
    ap = os.path.join(out_dir, 'answer.json')
    if r.returncode != 0:
        return None, 'runtime error: ' + r.stderr.strip()[:200]
    if not os.path.exists(ap):
        return None, 'no answer.json produced'
    return json.load(open(ap)), None

def compare(d, exp, out_dir, label, toln=8):
    check(d['grid'] == exp['grid'], '%s: grid mismatch' % label)
    check(d.get('member_secret') == exp['member_secret'], '%s: secret mismatch' % label)
    check(d.get('code_value') == exp['code_value'], '%s: code value %r != %r' % (
        label, d.get('code_value'), exp['code_value']))
    check(d.get('print_word') == exp['print_word'], '%s: print word %r != %r' % (
        label, d.get('print_word'), exp['print_word']))
    check(canon(d.get('shapes')) == canon(exp['shapes']), '%s: shapes mismatch' % label)
    for k in ('line_inliers', 'plane_inliers', 'rigid_inliers'):
        got = int(d.get(k, -1)); want = int(exp[k])
        check(abs(got - want) <= toln, '%s: %s %d != %d' % (label, k, got, want))
    # OCR-based image checks (competency 2 and 3)
    for img, key in (('render_a.png', 'render_a'), ('render_b.png', 'render_b')):
        p = os.path.join(out_dir, img)
        if not os.path.exists(p):
            fail('%s: missing %s' % (label, img)); continue
        got = ocr_file(p); want = exp[key]
        check(normalize(got) == normalize(want), '%s: OCR %s read %r != %r' % (
            label, img, normalize(got), normalize(want)))
    pp = os.path.join(out_dir, 'print.png')
    if not os.path.exists(pp):
        fail('%s: missing print.png' % label)
    else:
        check(normalize(ocr_file(pp)) == normalize(exp['print_word']),
           '%s: print.png OCR err' % label)

# ---- 1) visible case: pristine scenario re-run ----
d, err = run_scenario('/app/scenario', '/tmp/visout')
if err:
    fail('visible run: ' + err)
elif os.path.exists('/tests/expected.json'):
    compare(d, json.load(open('/tests/expected.json')), '/tmp/visout', 'visible')

# Verify the /app/answer.json deliverable (created by running solve.py on the
# shipped scenario) matches the visible expectation.
if os.path.exists('/app/answer.json') and os.path.exists('/tests/expected.json'):
    try:
        ap_data = json.load(open('/app/answer.json'))
        compare(ap_data, json.load(open('/tests/expected.json')),
                '/app', '/app/answer.json deliverable')
    except Exception as e:
        fail('deliverable /app/answer.json: ' + str(e))

# ---- 2) hidden cases ----
hidden = '/tests/hidden'
if os.path.isdir(hidden):
    cases = sorted(n for n in os.listdir(hidden)
                   if os.path.isdir(os.path.join(hidden, n)))
    check(len(cases) >= 2, 'expected >=2 hidden cases')
    for i, case in enumerate(cases):
        src = os.path.join(hidden, case)
        work = '/tmp/s3c/%s' % case
        shutil.rmtree(work, ignore_errors=True)
        out = work + '_out'
        shutil.rmtree(out, ignore_errors=True)
        dub = run_scenario(src, out)
        d, err = dub
        exp_path = os.path.join(src, 'expected.json')
        if not os.path.exists(exp_path):
            fail('%s: no expected.json' % case); continue
        expected = json.load(open(exp_path))
        if err:
            fail('%s: %s' % (case, err)); continue
        compare(d, expected, out, case)

if failures:
    print('FAILURES:')
    for m in failures:
        print('  - ' + m)
    open('/logs/verifier/reward.txt', 'w').write('0')
    sys.exit(0)
open('/logs/verifier/reward.txt', 'w').write('1')
print('ALL PASS')
sys.exit(0)
PY