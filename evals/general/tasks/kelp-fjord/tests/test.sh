#!/bin/bash
# Verifier for kelp-fjord: decrypts /app/records.gpg, compares the extracted
# tree to /app/exports, checks the OpenPGP packet cipher is 9 (AES-256),
# checks /app/cipher-choice.txt, scans for leftover plaintext archives, then
# reruns /app/seal.sh on hidden mutations (new files + new passphrase) and
# repeats the audit. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

python3 - <<'PY'
import atexit, hashlib, os, shutil, subprocess, sys, tempfile

fails = []
WORK = '/tmp/kf_verify'


def safety():
    try:
        os.makedirs('/logs/verifier', exist_ok=True)
        if not os.path.exists('/logs/verifier/reward.txt'):
            with open('/logs/verifier/reward.txt', 'w') as fh:
                fh.write('0\n')
    except Exception:
        pass


atexit.register(safety)


def run(cmd, timeout=120):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception as e:
        return subprocess.CompletedProcess(cmd, -1, '', 'raised %s' % e)


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def tree(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for f in filenames:
            p = os.path.join(dirpath, f)
            out[os.path.relpath(p, root)] = sha(p)
    return out


def strip_prefix(rels):
    parts = [r.split('/') for r in rels]
    if not parts:
        return rels
    first = parts[0][0]
    if first in ('.', '') :
        stripped = ['/'.join(p[1:]) if len(p) > 1 else p[0] for p in parts]
        return stripped
    if all(len(p) > 1 and p[0] == first for p in parts):
        return ['/'.join(p[1:]) for p in parts]
    return rels


def leftover_archives():
    hits = []
    for base in ('/app', '/tmp'):
        for dirpath, dirnames, filenames in os.walk(base):
            if dirpath.startswith(WORK):
                dirnames[:] = []
                continue
            for f in filenames:
                if f.endswith(('.tar', '.tar.gz', '.tgz', '.gz')):
                    hits.append(os.path.join(dirpath, f))
    return hits


def audit(label):
    """Full audit against the CURRENT /app/exports and /app/.seal-key."""
    if not os.path.isfile('/app/records.gpg'):
        fails.append('%s: /app/records.gpg missing' % label)
        return
    if not os.path.isfile('/app/seal.sh'):
        fails.append('%s: /app/seal.sh missing' % label)
        return
    if not (os.stat('/app/seal.sh').st_mode & 0o111):
        fails.append('%s: /app/seal.sh not executable' % label)
    # cipher choice
    try:
        cc = open('/app/cipher-choice.txt').read().strip()
    except Exception:
        cc = ''
    if 'AES256' not in cc.replace('-', '').upper():
        if 'AES256' not in cc.upper().replace('-', ''):
            fails.append('%s: cipher-choice.txt does not name AES-256: %r' % (label, cc))
    # packets
    try:
        pas = open('/app/.seal-key').read().strip()
    except Exception as e:
        fails.append('%s: cannot read /app/.seal-key: %s' % (label, e))
        return
    d = run(['gpg', '--batch', '--pinentry-mode', 'loopback',
             '--passphrase', pas, '--list-packets', '/app/records.gpg'])
    if 'cipher 9' not in (d.stdout + d.stderr):
        fails.append('%s: records.gpg not AES-256 (cipher 9 missing)' % label)
        return
    # decrypt + extract
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK, exist_ok=True)
    dec = os.path.join(WORK, 'dec.tar.gz')
    g = run(['gpg', '--batch', '--yes', '--pinentry-mode', 'loopback',
             '--passphrase', pas, '--decrypt', '-o', dec, '/app/records.gpg'])
    if g.returncode != 0 or not os.path.isfile(dec):
        fails.append('%s: decryption failed: %s' % (label, (g.stderr or '')[-200:]))
        return
    exdir = os.path.join(WORK, 'x')
    os.makedirs(exdir)
    exdir = os.path.join(WORK, 'x')
    shutil.rmtree(exdir, ignore_errors=True)
    os.makedirs(exdir)
    t = run(['tar', '-xzf', dec, '-C', exdir])
    if t.returncode != 0:
        fails.append('%s: extraction failed: %s' % (label, (t.stderr or '')[-200:]))
        return
    want = tree('/app/exports')
    got_tree = tree(exdir)
    # strip a single common top-level directory (e.g. 'exports/' or './')
    firsts = set(k.split('/')[0] for k in got_tree)
    if len(firsts) == 1 and next(iter(firsts)) not in ('.', ''):
        got = {'/'.join(k.split('/')[1:]): got_tree[k] for k in got_tree}
    else:
        got = dict(got_tree)
    if set(got.keys()) != set(want.keys()):
        fails.append('%s: extracted file set differs from /app/exports' % label)
        return
    for rel, h in want.items():
        if rel not in got:
            fails.append('%s: missing exported file %s after decrypt' % (label, rel))
            return
        if got[rel] != h:
            fails.append('%s: bytes differ for %s after decrypt' % (label, rel))
            return
    # leftover plaintext archives
    hits = leftover_archives()
    if hits:
        fails.append('%s: leftover plaintext archives: %s' % (label, hits[:5]))


def main():
    # visible audit
    audit('visible')
    # hidden case 1: modified + extra file, new passphrase
    if not fails:
        try:
            shutil.copy('/tests/hidden/case1/panel_results.csv',
                        '/app/exports/panel_results.csv')
            shutil.copy('/tests/hidden/case1/adverse_events.csv',
                        '/app/exports/adverse_events.csv')
            shutil.copy('/tests/hidden/case1/passphrase.txt', '/app/.seal-key')
        except Exception as e:
            fails.append('case1 setup failed: %s' % e)
        r = run(['bash', '/app/seal.sh'], timeout=180)
        if r.returncode != 0:
            fails.append('case1: seal.sh exited %d: %s' % (r.returncode, (r.stderr or '')[-200:]))
        audit('case1')
    # hidden case 2: nested subdirectory + new file, another passphrase
    if not fails:
        try:
            os.makedirs('/app/exports/audits/2026', exist_ok=True)
            shutil.copy('/tests/hidden/case2/audits/2026/access_audit.csv',
                        '/app/exports/audits/2026/access_audit.csv')
            shutil.copy('/tests/hidden/case2/shipments.csv',
                        '/app/exports/shipments.csv')
            shutil.copy('/tests/hidden/case2/passphrase.txt', '/app/.seal-key')
        except Exception as e:
            fails.append('case2 setup failed: %s' % e)
        r = run(['bash', '/app/seal.sh'], timeout=180)
        if r.returncode != 0:
            fails.append('case2: seal.sh exited %d: %s' % (r.returncode, (r.stderr or '')[-200:]))
        audit('case2')
    for f in fails:
        print('FAIL: %s' % f)
    print('verify failures: %d' % len(fails))
    return 1 if fails else 0


rc = main()
with open('/logs/verifier/reward.txt', 'w') as fh:
    fh.write('%d\n' % (0 if rc else 1))
sys.exit(rc)
PY
rc=$?
[ $rc -eq 0 ] && echo 1 > /logs/verifier/reward.txt || echo 0 > /logs/verifier/reward.txt
exit 0
