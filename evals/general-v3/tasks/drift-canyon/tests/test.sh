#!/bin/bash
# Verifier for tasks/drift-canyon (executes-deliverable).
# Re-invokes the deliverable /app/solve.py, then independently checks every
# competency gate: recovered git work, bundle branches via HEAD, the assembled
# profile site, an SSH password-auth git server (clone + push), the executable
# reconstruction script with the preserved source listing, and the answer.json
# report.  Finally it runs solve.py's `repair` mode over fresh hidden git
# scenarios and verifies the produced state independently.  Writes a numeric
# reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
mkdir -p /run/sshd

# Deliverable must exist and be executable.
if [ ! -f /app/solve.py ] || [ ! -x /app/solve.py ]; then
  echo "missing/not-executable deliverable /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# Ensure the SSH daemon runs so the served-repo checks are meaningful.
if ! pgrep -x sshd >/dev/null 2>&1; then
  /usr/sbin/sshd
  sleep 1
fi

python3 - <<'PYEOF'
import json
import os
import subprocess
import sys
import tarfile

failures = []

def run(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          env=env)

def bundle_head(bpath):
    """Advertised HEAD sha of a git bundle, read standalone (no repo needed)."""
    r = run(['git', 'bundle', 'list-heads', bpath])
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) >= 2 and p[1] == 'HEAD':
            return p[0]
    return None

# ---- A. Re-invoke the deliverable fresh (reproducible reconstruction) ----
r = run(['python3', '/app/solve.py'])
if r.returncode != 0:
    failures.append('solve.py failed to re-run')
if not os.path.exists('/app/answer.json'):
    failures.append('solve.py did not write /app/answer.json')

SITE = '/app/site'

# ---- B. Assembled profile site (about / blog / publications) ----
def read(p):
    try:
        return open(p).read()
    except OSError:
        return ''
pages = {
    'index.html': 'Marlow Bayne',
    'about.html': 'barnacle recruitment',
    'blog.html': 'Into the Ember Mud',
    'publications.html': 'Intertidal Letters',
}
for fn, marker in pages.items():
    p = os.path.join(SITE, fn)
    if not os.path.exists(p):
        failures.append('missing site page %s' % fn)
    elif marker not in read(p):
        failures.append('site page %s lacks marker %r' % (fn, marker))
for post in ('blog/into-the-ember-mud.html', 'blog/harbor-at-low-water.html'):
    if not os.path.exists(os.path.join(SITE, post)):
        failures.append('missing blog post %s' % post)
if 'Harbor at Low Water' not in read(os.path.join(SITE, 'blog.html')):
    failures.append('blog listing missing second post title')

# ---- C. Recovered lost work committed to main ----
rr = run(['git', '-C', SITE, 'branch', '--list', 'main'])
if rr.returncode != 0 or 'main' not in rr.stdout:
    failures.append('no main branch')
rr = run(['git', '-C', SITE, 'ls-files', '--error-unmatch',
          'writing/sketches/story-notes.txt'])
if rr.returncode != 0:
    failures.append('recovered draft not tracked on main')
elif 'cove lantern' not in read(os.path.join(SITE, 'writing/sketches/story-notes.txt')):
    failures.append('recovered draft has wrong content')

# ---- D. Bundle branches checked out from HEAD references ----
for bfile, branch in (('on-guide.bundle', 'on-guide'),
                      ('fieldnotes.bundle', 'fieldnotes')):
    head = bundle_head(os.path.join('/app/bundles', bfile))
    if head is None:
        failures.append('could not read HEAD of %s' % bfile)
        continue
    got = run(['git', '-C', SITE, 'rev-parse', branch])
    if got.returncode != 0:
        failures.append('bundle branch %s is missing' % branch)
    elif got.stdout.strip() != head:
        failures.append('bundle branch %s != bundle HEAD' % branch)

# ---- E. SSH password-auth git server: clone + push ----
env = dict(os.environ)
env['GIT_SSH_COMMAND'] = ('sshpass -p lantern-9 ssh '
                          '-o StrictHostKeyChecking=no '
                          '-o UserKnownHostsFile=/dev/null -p 22 '
                          '-o PreferredAuthentications=password '
                          '-o PubkeyAuthentication=no')
sh = '/tmp/sshcheck'
run(['rm', '-rf', sh])
clone = run(['git', 'clone', '-q',
             'gitdev@127.0.0.1:/srv/git/marlow.git', sh], env=env)
if clone.returncode != 0:
    failures.append('ssh password clone failed: ' + (clone.stderr or '')[-200:])
else:
    for br in ('origin/on-guide', 'origin/fieldnotes', 'origin/main'):
        where = run(['git', '-C', sh, 'rev-parse', '--verify', br], env=env)
        if where.returncode != 0:
            failures.append('cloned repo lacks %s' % br)
    for fn in pages:
        if not os.path.exists(os.path.join(sh, fn)):
            failures.append('cloned repo lacks site page %s' % fn)
    if not os.path.exists(os.path.join(sh, 'writing/sketches/story-notes.txt')):
        failures.append('cloned repo lacks recovered draft')
    commit = run(['git', '-C', sh, '-c', 'user.name=v',
                  '-c', 'user.email=v@v', 'commit', '-q', '--allow-empty',
                  '-m', 'probe'], env=env)
    push = run(['git', '-C', sh, 'push', '-q', 'origin',
                'HEAD:refs/heads/verifier-probe'], env=env)
    if push.returncode != 0:
        failures.append('ssh push failed: ' + (push.stderr or '')[-200:])

# ---- F. Executable reconstruction script + preserved source listing ----
rec = '/app/site/deploy/reconstruct.sh'
if not os.access(rec, os.X_OK):
    failures.append('reconstruct.sh is not executable')
# The script body must be byte-for-byte the fixture that was committed.
expected_reconstruct_body = """#!/bin/sh
# Rebuild the Marlow profile site pages under OUT from the notes under NOTES.
# Left non-executable on purpose: the reconstruction script's executable bit
# is the last thing to be restored before the site can be shipped.
set -eu
NOTES_DIR="${1:-/app/notes}"
OUT_DIR="${2:-/app/site}"
python3 - "$NOTES_DIR" "$OUT_DIR" <<'PY'
import os, sys
notes, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
bio = open(os.path.join(notes, "bio.md")).read()
(open(os.path.join(out, "reconstructed.txt"), "w").write(bio))
PY
echo "site reconstructed"
"""
if read(rec).rstrip('\r\n') != expected_reconstruct_body.rstrip('\r\n'):
    failures.append('reconstruct.sh content was altered')

expected_listing = """deploy/reconstruct.sh
notes/bio.md
notes/posts/ember.md
notes/posts/harbor.md
notes/pubs.md
personal-plan.txt
writing/sketches/story-notes.txt
site/README.md
"""
if read('/app/listing.txt') != expected_listing:
    failures.append('listing.txt was altered from the source listing')

# ---- G. answer.json report cross-check ----
if os.path.exists('/app/answer.json'):
    try:
        ans = json.load(open('/app/answer.json'))
    except Exception:
        ans = {}
    for br in ('on-guide', 'fieldnotes'):
        if br not in ans.get('bundle_branches', []):
            failures.append('answer.json omits bundle branch %s' % br)
    for fp in ans.get('site_pages', []):
        if not os.path.exists(os.path.join(SITE, fp)):
            failures.append('answer.json site_page missing on disk: %s' % fp)
    if ans.get('recovered_present') is not True:
        failures.append('answer.json recovered_present is not true')
    if ans.get('deploy_executable') is not True:
        failures.append('answer.json deploy_executable is not true')
    if ans.get('listing_preserved') is not True:
        failures.append('answer.json listing_preserved is not true')
    if ans.get('ssh_user') != 'gitdev' or ans.get('password') != 'lantern-9':
        failures.append('answer.json ssh identity fields wrong')
    if ans.get('bare_repo') != '/srv/git/marlow.git':
        failures.append('answer.json bare_repo wrong')

# ---- H. hidden repair scenarios (fresh standalone git states) ----
def branches_of(repo):
    r = run(['git', '-C', repo, 'for-each-ref', 'refs/heads',
             '--format=%(refname:short)'])
    return [x.strip() for x in r.stdout.splitlines() if x.strip()]

def find_lost(repo, path, target):
    sl = run(['git', '-C', repo, 'stash', 'list'])
    if 'stash@{' in sl.stdout:
        got = run(['git', '-C', repo, 'show', 'stash@{0}:' + path])
        if got.returncode == 0:
            return got.stdout
    for b in branches_of(repo):
        if b == target:
            continue
        ls = run(['git', '-C', repo, 'ls-tree', '-r', '--name-only', b])
        if path in ls.stdout.splitlines():
            got = run(['git', '-C', repo, 'show', b + ':' + path])
            if got.returncode == 0:
                return got.stdout
    return None

hidden_dirs = sorted(
    d for d in (os.path.join('/tests/hidden', x)
                for x in os.listdir('/tests/hidden'))
    if os.path.isdir(d) and os.path.exists(os.path.join(d, 'plan.json')))

if not hidden_dirs:
    failures.append('no hidden repair scenarios found')

for hd in hidden_dirs:
    name = os.path.basename(hd)
    work = '/tmp/repair_' + name
    run(['rm', '-rf', work])
    os.makedirs(os.path.join(work, 'bundles'))
    src = os.path.join(work, 'site')
    # pristine is an untouched reference copy used to derive the expected lost
    # bytes (before the repair path mutates the working copy).
    pristine = os.path.join(work, 'pristine')
    try:
        with tarfile.open(os.path.join(hd, 'repo.tar.gz')) as tf:
            tf.extractall(src)
        with tarfile.open(os.path.join(hd, 'repo.tar.gz')) as tf:
            tf.extractall(pristine)
    except Exception as exc:
        failures.append('%s: repo.tar.gz unreadable: %r' % (name, exc))
        continue
    # the fresh repos come shipped to us; standardize ownership to the current
    # user so git can operate on them without a dubious-ownership complaint.
    subprocess.run(['chown', '-R', 'root:root', src])
    subprocess.run(['chown', '-R', 'root:root', pristine])
    plan = json.load(open(os.path.join(hd, 'plan.json')))
    for f in os.listdir(os.path.join(hd, 'bundles')):
        subprocess.run(['cp', os.path.join(hd, 'bundles', f),
                        os.path.join(work, 'bundles', f)])
    subprocess.run(['cp', os.path.join(hd, 'plan.json'),
                    os.path.join(work, 'plan.json')])

    out = run(['python3', '/app/solve.py', 'repair', '--home', work])
    if out.returncode != 0:
        failures.append('%s: repair crashed (rc=%d)' % (name, out.returncode))
        continue
    try:
        res = json.loads(out.stdout)
    except Exception:
        failures.append('%s: repair did not print valid JSON' % name)
        continue

    target = plan.get('default_branch')
    brs = branches_of(src)
    has_target = target in brs

    lost_ok = True
    if plan.get('lost'):
        path = plan['lost']['path']
        expected = find_lost(pristine, path, target)
        if expected is None:
            failures.append('%s: could not locate lost work independently'
                            % name)
            lost_ok = False
        else:
            actual = read(os.path.join(src, path))
            tracked = run(['git', '-C', src, 'ls-files', '--error-unmatch',
                           path]).returncode == 0
            if actual != expected or not tracked:
                failures.append(
                    '%s: lost work not restored onto %s with correct bytes'
                    % (name, target))
                lost_ok = False

    bundle_ok = True
    for b in plan.get('bundles') or []:
        bf = os.path.join(hd, 'bundles', b['filename'])
        branch = b['branch']
        if os.path.exists(bf):
            head = bundle_head(bf)
            got = run(['git', '-C', src, 'rev-parse', branch])
            if head is None or got.returncode != 0 or got.stdout.strip() != head:
                failures.append('%s: bundle branch %s != HEAD (head=%s got=%s rc=%s)'
                                 % (name, branch, head,
                                    got.stdout.strip() if got.returncode == 0
                                    else got.returncode, got.returncode))
                bundle_ok = False
        else:
            bundle_ok = False
            if branch in brs:
                failures.append('%s: branch %s should be absent' % (name, branch))

    expected_ok = bool(has_target and lost_ok and bundle_ok)
    if res.get('ok') is not expected_ok:
        failures.append('%s: ok=%r but expected %r' % (name, res.get('ok'),
                                                       expected_ok))

if failures:
    print('FAILURES:')
    for m in failures:
        print('  - ' + m)
    open('/logs/verifier/reward.txt', 'w').write('0')
    sys.exit(0)

print('ALL PASS')
open('/logs/verifier/reward.txt', 'w').write('1')
sys.exit(0)
PYEOF