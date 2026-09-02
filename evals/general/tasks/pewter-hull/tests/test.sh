#!/bin/bash
# Verifier for pewter-hull (executes-deliverable).
#
# Executes /app/framer.py on the visible fixture and on hidden cases:
# valid splits of unseen (input, cap) pairs must round-trip byte-exactly and
# audit clean; a corrupted frame set and bad invocations must fail closed.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import glob
import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile

FRAMER = '/app/framer.py'
HD = '/tests/hidden'
MAGIC = b'FRM1'
HEADER = 16
probs = []


def check(name, cond, detail=''):
    if not cond:
        probs.append('%s  <%s>' % (name, detail))


def run(*args):
    return subprocess.run(['python3', FRAMER] + list(args),
                          capture_output=True, text=True, timeout=120)


def outdir():
    return tempfile.mkdtemp(prefix='framer_v_')


def parse_manifest(d):
    try:
        with open(os.path.join(d, 'manifest.json')) as fh:
            return json.load(fh)
    except Exception as exc:  # noqa: BLE001
        check('manifest_parse_%s' % d, False, str(exc))
        return None


def check_frames(d, m, data, cap):
    """Structural validation of a split against its source bytes."""
    ppr = cap - HEADER
    total = int(math.ceil(len(data) / float(ppr))) if data else 0
    check('frames_count_%s' % d, m.get('frames') == total, m.get('frames'))
    check('payload_per_frame_%s' % d,
          m.get('payload_per_frame') == ppr, m.get('payload_per_frame'))
    check('size_%s' % d, m.get('size') == len(data), m.get('size'))
    check('magic_%s' % d, m.get('magic') == 'FRM1', m.get('magic'))
    check('sha_%s' % d, m.get('sha256') == hashlib.sha256(data).hexdigest())
    files = m.get('frame_files') or []
    check('frame_files_len_%s' % d, len(files) == total, len(files))
    hashes = m.get('frame_sha256') or []
    check('frame_sha_len_%s' % d, len(hashes) == total, len(hashes))
    for i in range(total):
        fname = 'frame_%04d.frag' % i
        if i < len(files):
            check('frame_name_%s_%d' % (d, i), files[i] == fname, files[i])
        path = os.path.join(d, fname)
        if not os.path.isfile(path):
            check('frame_exists_%s_%d' % (d, i), False, path)
            continue
        blob = open(path, 'rb').read()
        check('frame_cap_%s_%d' % (d, i), len(blob) <= cap, len(blob))
        # every frame exactly CAP except the last
        want = cap if i < total - 1 else HEADER + len(data) - i * ppr
        check('frame_len_%s_%d' % (d, i), len(blob) == want,
              (len(blob), want))
        check('frame_magic_%s_%d' % (d, i), blob[:4] == MAGIC)
        idx, tot, plen = struct.unpack('>III', blob[4:HEADER])
        check('frame_hdr_%s_%d' % (d, i),
              (idx, tot, plen) == (i, total, len(blob) - HEADER),
              (idx, tot, plen))
        if i < len(hashes):
            check('frame_sha_%s_%d' % (d, i),
                  hashes[i] == hashlib.sha256(blob).hexdigest())


# ---- deliverable exists ----
check('framer_exists', os.path.isfile(FRAMER), FRAMER)
if not os.path.isfile(FRAMER):
    print('verify failures:', probs)
    sys.exit(1)

payload = open('/app/uplink/payload.bin', 'rb').read()
cap = int(open('/app/uplink/cap.txt').read().strip())

# ---- visible case: execute the tool end to end ----
v = outdir()
r = run('split', '/app/uplink/payload.bin', str(cap), v)
check('visible_split_exit0', r.returncode == 0, r.stderr[-200:])
m = parse_manifest(v)
exp = json.load(open('/tests/expected.json'))
if m:
    check('visible_manifest',
          (m.get('frames'), m.get('cap'), m.get('size'),
           m.get('payload_per_frame'), m.get('sha256')) ==
          (exp['frames'], exp['cap'], exp['size'],
           exp['payload_per_frame'], exp['sha256']), m.get('frames'))
    check_frames(v, m, payload, cap)
ra = run('audit', v)
check('visible_audit_ok', ra.returncode == 0 and 'AUDIT_OK' in ra.stdout,
      (ra.stdout + ra.stderr)[-200:])
back = os.path.join(outdir(), 'back.bin')
rj = run('join', v, back)
check('visible_join_exit0', rj.returncode == 0, rj.stderr[-200:])
check('visible_join_bytes',
      os.path.isfile(back) and open(back, 'rb').read() == payload)

# ---- visible deliverable /app/frames must be a genuine split ----
vman = '/app/frames/manifest.json'
check('visible_deliverable_manifest', os.path.isfile(vman), vman)
ra2 = run('audit', '/app/frames')
check('visible_deliverable_audit', ra2.returncode == 0
      and 'AUDIT_OK' in ra2.stdout, (ra2.stdout + ra2.stderr)[-200:])
back2 = os.path.join(outdir(), 'back2.bin')
rj2 = run('join', '/app/frames', back2)
check('visible_deliverable_join', rj2.returncode == 0
      and os.path.isfile(back2)
      and open(back2, 'rb').read() == payload,
      rj2.stderr[-200:])

# ---- hidden cases: unseen (input, cap) pairs must split + round-trip ----
for case in ('tiny', 'exact', 'large', 'empty'):
    base = os.path.join(HD, case)
    data = open(os.path.join(base, 'input.bin'), 'rb').read()
    c = int(open(os.path.join(base, 'cap.txt')).read().strip())
    d = outdir()
    r = run('split', os.path.join(base, 'input.bin'), str(c), d)
    check('hidden_%s_split_exit0' % case, r.returncode == 0, r.stderr[-200:])
    m = parse_manifest(d)
    if m:
        check('hidden_%s_manifest_input' % case,
              m.get('input') == 'input.bin', m.get('input'))
        check_frames(d, m, data, c)
    ra = run('audit', d)
    check('hidden_%s_audit' % case, ra.returncode == 0
          and 'AUDIT_OK' in ra.stdout, (ra.stdout + ra.stderr)[-200:])
    bpath = os.path.join(outdir(), 'rt.bin')
    rj = run('join', d, bpath)
    check('hidden_%s_join' % case, rj.returncode == 0
          and os.path.isfile(bpath)
          and open(bpath, 'rb').read() == data, rj.stderr[-200:])

# ---- hidden corrupt set: join/audit must fail closed, OUTPUT not written ----
corr = os.path.join(HD, 'corrupt')
cb = os.path.join(outdir(), 'must_not_exist.bin')
if os.path.isfile(cb):
    os.remove(cb)
rj = run('join', corr, cb)
check('corrupt_join_fails', rj.returncode != 0, rj.returncode)
check('corrupt_join_no_output', not os.path.isfile(cb), cb)
ra = run('audit', corr)
check('corrupt_audit_fails', ra.returncode != 0, ra.returncode)

# ---- bad invocations fail closed and write nothing ----
d1 = os.path.join(outdir(), 'nope')
r = run('split', '/nonexistent/input.bin', '64', d1)
check('err_missing_input', r.returncode != 0 and not os.path.exists(d1),
      r.returncode)
d2 = os.path.join(outdir(), 'smallcap')
r = run('split', '/app/uplink/payload.bin', '16', d2)
check('err_cap_too_small', r.returncode != 0 and not os.path.exists(d2),
      r.returncode)
d3 = os.path.join(outdir(), 'badcap')
r = run('split', '/app/uplink/payload.bin', '48x', d3)
check('err_cap_non_integer', r.returncode != 0 and not os.path.exists(d3),
      r.returncode)

print('verify failures:', probs)
sys.exit(1 if probs else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
