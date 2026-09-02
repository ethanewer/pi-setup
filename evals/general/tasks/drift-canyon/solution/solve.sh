#!/bin/bash
# Oracle for tasks/drift-canyon.
# Writes the reconstruction driver /app/solve.py, makes it executable, and runs
# it for real to reconstruct the whole git+ssh+site stack and write answer.json.
# It never reads /tests.
set -euo pipefail

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""drift-canyon reconstruction driver.

Default run reconstructs the private profile/site stack from fixtures under /app:
  * assembles the profile pages (index/about/blog/publications) from /app/notes,
  * restores the lost stash'ed work onto the main branch,
  * checks out two branches carried by git bundles via their HEAD reference,
  * serves a bare repository over SSH owned by a password-auth user, and
  * flags the legacy rebuild script as executable while leaving the source
    listing untouched.

Repair mode (used by the verifier on fresh hidden scenarios):
    python3 solve.py repair --home DIR
reads DIR/plan.json describing a small standalone git repo at DIR/site plus
bundle inputs under DIR/bundles, reconstructs lost work and bundle branches
there, and prints a JSON status report.  It must never crash, even when the
default branch is missing, the lost work is absent, or a bundle input is
missing/invalid.
"""
import json
import os
import re
import subprocess
import sys
import time


def G(cwd, *args, **kw):
    return subprocess.run(['git'] + list(args), cwd=cwd,
                          capture_output=True, text=True, **kw)


def run(args, cwd=None):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True)


def branches(cwd):
    r = G(cwd, 'for-each-ref', 'refs/heads', '--format=%(refname:short)')
    return [x.strip() for x in r.stdout.splitlines() if x.strip()]


def current(cwd):
    r = G(cwd, 'rev-parse', '--abbrev-ref', 'HEAD')
    return r.stdout.strip()


def commit_if_changed(cwd, message):
    G(cwd, 'add', '-A')
    s = G(cwd, 'status', '--porcelain').stdout
    if s.strip():
        r = G(cwd, 'commit', '-q', '-m', message)
        if r.returncode != 0:
            G(cwd, 'commit', '-q', '-m', message)


def ensure_identity(repo):
    if not G(repo, 'config', 'user.name').stdout.strip():
        G(repo, 'config', 'user.name', 'Reconstructor')
    if not G(repo, 'config', 'user.email').stdout.strip():
        G(repo, 'config', 'user.email', 'recon@localhost')


def bundle_heads(bpath):
    """Return the {refname -> sha} mapping advertised by a git bundle."""
    r = subprocess.run(['git', 'bundle', 'list-heads', bpath],
                       capture_output=True, text=True)
    out = {}
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) >= 2:
            out[p[1]] = p[0]
    return out


def bundle_tip(cwd, bpath):
    """Return the tip commit referenced by a bundle's HEAD after importing the
    bundle's objects into `cwd`.  Falls back to FETCH_HEAD, then to the single
    remaining advertised ref, when the HEAD reference is absent/ambiguous."""
    r = G(cwd, 'fetch', bpath)
    if r.returncode != 0:
        return None
    heads = bundle_heads(bpath)
    sha = heads.get('HEAD')
    if not sha:
        fh = G(cwd, 'rev-parse', '--verify', 'FETCH_HEAD')
        if fh.returncode == 0:
            sha = fh.stdout.strip()
    if not sha:
        shas = {s for name, s in heads.items() if name != 'HEAD'}
        if len(shas) == 1:
            sha = shas.pop()
    return sha


def recover_lost(repo, rel):
    """Bring lost uncommitted / off-branch work for the file `rel` onto the
    current working copy and stage it.  Checks the working tree first, then any
    stash entry, then any other local branch carrying that path."""
    full = os.path.join(repo, rel)
    if os.path.exists(full):
        G(repo, 'add', '--', rel)
        return True
    if 'stash@{' in G(repo, 'stash', 'list').stdout:
        r = G(repo, 'stash', 'pop')
        if r.returncode != 0:
            G(repo, 'stash', 'apply')
        if os.path.exists(full):
            G(repo, 'add', '--', rel)
            return True
    cur = current(repo)
    for b in branches(repo):
        if b == cur:
            continue
        ls = G(repo, 'ls-tree', '-r', '--name-only', b).stdout.splitlines()
        if rel in ls:
            content = G(repo, 'show', '%s:%s' % (b, rel)).stdout
            parent = os.path.dirname(full)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with open(full, 'w') as f:
                f.write(content)
            G(repo, 'add', '--', rel)
            return True
    return False


# ---------------------------------------------------------------------------
# repair mode (fresh hidden scenarios)
# ---------------------------------------------------------------------------

def repair_run(home, plan):
    repo = os.path.join(home, 'site')
    ensure_identity(repo)
    target = plan.get('default_branch')
    brs = branches(repo)
    has_target = target in brs
    recs = []
    lost = plan.get('lost')
    if lost and has_target:
        try:
            if current(repo) != target:
                G(repo, 'checkout', '-q', target)
            if recover_lost(repo, lost.get('path')):
                recs.append(lost.get('path'))
                commit_if_changed(repo, 'repair: restore lost work')
        except Exception:  # noqa: BLE001
            recs = []
    branch_map = {}
    all_branch_ok = True
    for b in plan.get('bundles') or []:
        name = b.get('branch')
        fname = os.path.join(home, 'bundles', b.get('filename', ''))
        if not os.path.exists(fname):
            branch_map[name] = None
            all_branch_ok = False
            continue
        sha = bundle_tip(repo, fname)
        if not sha:
            branch_map[name] = None
            all_branch_ok = False
            continue
        G(repo, 'branch', '-q', '-f', name, sha)
        branch_map[name] = G(repo, 'rev-parse', name).stdout.strip()
    recovered_sat = (not lost) or bool(recs)
    ok = bool(has_target) and recovered_sat and all_branch_ok
    return {
        'scenario': plan.get('scenario'),
        'ok': bool(ok),
        'has_target': bool(has_target),
        'recovered': recs,
        'branches': branch_map,
    }


def repair_mode(args):
    home = None
    it = iter(args[1:])
    for tok in it:
        if tok == '--home':
            home = next(it, None)
    if not home:
        print(json.dumps({"ok": False, "status": "no-home"}))
        return 0
    # Hidden scenarios arrive as fresh directories whose writer may differ from
    # the current user; trust them explicitly before any git operation.
    subprocess.run(['git', 'config', '--global', '--add', 'safe.directory',
                    os.path.join(home, 'site')])
    try:
        with open(os.path.join(home, 'plan.json')) as f:
            plan = json.load(f)
        out = repair_run(home, plan)
    except Exception as exc:  # noqa: BLE001
        out = {"ok": False, "status": "error", "scenario": "unknown",
               "detail": repr(exc)}
    print(json.dumps(out, indent=2))
    return 0


# ---------------------------------------------------------------------------
# site assembly
# ---------------------------------------------------------------------------

def build_site(repo, notes_dir):
    """Turn the raw bio notes into a small personal profile website."""
    bio = open(os.path.join(notes_dir, 'bio.md')).read().strip()
    name = bio.splitlines()[0].strip()
    posts = {}
    for fn in sorted(os.listdir(os.path.join(notes_dir, 'posts'))):
        if not fn.endswith('.md'):
            continue
        text = open(os.path.join(notes_dir, 'posts', fn)).read().strip()
        title = text.splitlines()[0].strip()
        slug = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
        posts[slug] = (title, text)
    pubs = open(os.path.join(notes_dir, 'pubs.md')).read().strip()
    blog_dir = os.path.join(repo, 'blog')
    os.makedirs(blog_dir, exist_ok=True)

    nav = ('<nav><a href="index.html">Home</a> '
           '<a href="about.html">About</a> '
           '<a href="blog.html">Blog</a> '
           '<a href="publications.html">Publications</a></nav>')

    def page(title, body):
        return ('<html><head><title>%s</title></head><body>%s%s'
                '</body></html>' % (title, nav, body))

    open(os.path.join(repo, 'index.html'), 'w').write(
        page(name, '<h1>%s</h1><p>Personal profile site served over git.</p>'
             % name))
    open(os.path.join(repo, 'about.html'), 'w').write(
        page('About', '<h1>About</h1><pre>%s</pre>' % bio))
    entries = []
    for slug, (title, text) in posts.items():
        entries.append('<section><h2><a href="blog/%s.html">%s</a></h2></section>'
                       % (slug, title))
        open(os.path.join(blog_dir, '%s.html' % slug), 'w').write(
            page(title, '<h1>%s</h1><pre>%s</pre>' % (title, text)))
    open(os.path.join(repo, 'blog.html'), 'w').write(
        page('Blog', '<h1>Blog</h1>' + '\n'.join(entries)))
    open(os.path.join(repo, 'publications.html'), 'w').write(
        page('Publications', '<h1>Publications</h1><pre>%s</pre>' % pubs))


# ---------------------------------------------------------------------------
# ssh / bare repo
# ---------------------------------------------------------------------------

EXPECTED_LISTING = """deploy/reconstruct.sh
notes/bio.md
notes/posts/ember.md
notes/posts/harbor.md
notes/pubs.md
personal-plan.txt
writing/sketches/story-notes.txt
site/README.md
"""


def ensure_password_auth():
    cfg = '/etc/ssh/sshd_config'
    try:
        lines = open(cfg).read().splitlines()
    except OSError:
        lines = []
    out = []
    touched = False
    for line in lines:
        if re.match(r'^#?\s*PasswordAuthentication\s', line):
            if not touched:
                out.append('PasswordAuthentication yes')
                touched = True
            continue
        out.append(line)
    if not touched:
        out.extend(['', 'PasswordAuthentication yes'])
    open(cfg, 'w').write('\n'.join(out) + '\n')


def ensure_ssh_running():
    os.makedirs('/run/sshd', exist_ok=True)
    if subprocess.run(['pgrep', '-x', 'sshd']).returncode != 0:
        subprocess.run(['/usr/sbin/sshd'])
        time.sleep(1)


def ensure_ssh_user():
    r = subprocess.run(['id', '-u', 'gitdev'])
    if r.returncode != 0:
        subprocess.run(['useradd', '-m', '-s', '/bin/bash', 'gitdev'])
    subprocess.run(['chpasswd'], input='gitdev:lantern-9\n', text=True)


def main_reconstruct():
    NOTES = '/app/notes'
    SITE = '/app/site'
    BUNDLES = '/app/bundles'
    BARE = '/srv/git/marlow.git'

    build_site(SITE, NOTES)
    ensure_identity(SITE)
    if current(SITE) != 'main':
        G(SITE, 'checkout', '-q', 'main')

    lost = 'writing/sketches/story-notes.txt'
    recover_lost(SITE, lost)
    commit_if_changed(SITE, 'assemble profile site and restore lost draft')

    for bfile, branch in (('on-guide.bundle', 'on-guide'),
                          ('fieldnotes.bundle', 'fieldnotes')):
        sha = bundle_tip(SITE, os.path.join(BUNDLES, bfile))
        if sha:
            G(SITE, 'branch', '-q', '-f', branch, sha)

    ensure_ssh_user()
    ensure_password_auth()

    if not os.path.exists(os.path.join(BARE, 'HEAD')):
        os.makedirs('/srv/git', exist_ok=True)
        subprocess.run(['git', 'init', '--bare', BARE])
    subprocess.run(['git', 'config', '--global', '--add', 'safe.directory',
                    BARE])
    subprocess.run(['git', '--git-dir', BARE,
                    'config', 'receive.denyCurrentBranch', 'ignore'])
    # Push as root while the repo is still writable regardless of owner, then
    # hand the whole bare repo to the dedicated ssh user for serving.
    subprocess.run(['git', '-C', SITE, 'push', BARE, '--all', '--force'])
    subprocess.run(['git', '--git-dir', BARE, 'symbolic-ref', 'HEAD',
                    'refs/heads/main'])
    subprocess.run(['chown', '-R', 'gitdev:gitdev', BARE])
    subprocess.run(['chmod', '-R', 'ug+rwX,o+rX', BARE])
    subprocess.run(['chown', 'gitdev:gitdev', '/srv/git'])
    subprocess.run(['chown', 'gitdev:gitdev', '/srv'])

    ensure_ssh_running()

    os.chmod('/app/site/deploy/reconstruct.sh', 0o755)
    listing_preserved = (open('/app/listing.txt').read() == EXPECTED_LISTING)

    bundle_branches = [b for b in ('on-guide', 'fieldnotes')
                       if b in branches(SITE)]
    report = {
        "task": "drift-canyon",
        "main_branch": "main",
        "recovered": [lost],
        "recovered_present": os.path.exists(os.path.join(SITE, lost)),
        "bundle_branches": bundle_branches,
        "bare_repo": BARE,
        "ssh_user": "gitdev",
        "password": "lantern-9",
        "site_pages": ["index.html", "about.html", "blog.html",
                       "blog/into-the-ember-mud.html",
                       "blog/harbor-at-low-water.html",
                       "publications.html"],
        "deploy_executable":
            os.access('/app/site/deploy/reconstruct.sh', os.X_OK),
        "listing_preserved": listing_preserved,
    }
    with open('/app/answer.json', 'w') as f:
        json.dump(report, f, indent=2)


def main():
    args = sys.argv[1:]
    if args and args[0] == 'repair':
        return repair_mode(args)
    main_reconstruct()
    return 0


if __name__ == '__main__':
    sys.exit(main())
PYEOF

chmod +x /app/solve.py

python3 /app/solve.py
python3 /app/solve.py
test -f /app/answer.json && echo "oracle: /app/solve.py ran and wrote /app/answer.json"