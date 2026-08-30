#!/usr/bin/env bash
# Oracle for hollow-atlas: performs all five competency deliverables with real work.
# Never reads /tests.
set -euo pipefail

GIT_CONFIG_NOSYSTEM=1
OPS_NAME="ops"; OPS_EMAIL="ops@atlas.local"
export GIT_AUTHOR_NAME="$OPS_NAME" GIT_AUTHOR_EMAIL="$OPS_EMAIL"
export GIT_COMMITTER_NAME="$OPS_NAME" GIT_COMMITTER_EMAIL="$OPS_EMAIL"

mkdir -p /app/bin /app/ssh /app/deploy/aurora /app/deploy/marble

# ----------------------------------------------------------------- reusable helpers
cat > /app/bin/checkout.py <<'PY'
#!/usr/bin/env python3
"""Checkout branches from git bundles into a repository.

Usage: python3 checkout.py <bundle_dir> <git_repo_dir>
Prints one created local branch name per line.
"""
import glob, os, subprocess, sys

def run(cmd, cwd=None, check=False):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit("cmd failed: %s\n%s" % (' '.join(cmd), r.stderr[-500:]))
    return r

def main():
    bundle_dir, repo_dir = sys.argv[1], sys.argv[2]
    if not os.path.isdir(os.path.join(repo_dir, '.git')):
        run(['git', 'init', '-b', 'main', repo_dir], check=True)
    created = []
    for bundle in sorted(glob.glob(os.path.join(bundle_dir, '*.bundle'))):
        r = run(['git', 'bundle', 'list-heads', bundle])
        heads = []
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                heads.append((parts[0], parts[1]))
        branch_refs = [(h, ref) for h, ref in heads if ref.startswith('refs/heads/')]
        if branch_refs:
            for _hash, ref in branch_refs:
                run(['git', '-C', repo_dir, 'fetch', bundle, ref + ':' + ref], check=True)
                name = ref.rsplit('/', 1)[-1]
                created.append(name)
        else:
            # bundle has only a bare HEAD: fall back to the bundle HEAD commit.
            if heads:
                h = heads[0][0]
                base = os.path.basename(bundle)
                if base.endswith('.bundle'):
                    base = base[:-7]
                run(['git', '-C', repo_dir, 'branch', base, h], check=True)
                created.append(base)
    sys.stdout.write("\n".join(created) + ("\n" if created else ""))

if __name__ == '__main__':
    main()
PY
chmod +x /app/bin/checkout.py

cat > /app/bin/sanitize.py <<'PY'
#!/usr/bin/env python3
"""Remove the external upload-sink token from non-comment workflow lines.

Usage: python3 sanitize.py <in> <out>
A line is a comment when its first non-whitespace char is '#'. Every NON-comment
line that contains `nightfall-ops.example` (case-insensitive) is dropped entirely;
all other lines are preserved byte-for-byte.
"""
import sys

TOKEN = 'nightfall-ops.example'

def main():
    inp, out = sys.argv[1], sys.argv[2]
    with open(inp) as f:
        lines = f.readlines()
    clean = []
    for ln in lines:
        if ln.lstrip().startswith('#'):
            clean.append(ln)
            continue
        if TOKEN in ln.lower():
            continue
        clean.append(ln)
    with open(out, 'w') as f:
        f.writelines(clean)

if __name__ == '__main__':
    main()
PY
chmod +x /app/bin/sanitize.py

# ---- 1) checkout branches from the bundles
python3 /app/bin/checkout.py /app/bundles /app/repo

git -C /app/repo config user.email "$OPS_EMAIL"
git -C /app/repo config user.name "$OPS_NAME"

# ---- 2) recover the lost stash onto feature-aurora and commit it
git -C /app/repo checkout -q feature-aurora
git -C /app/repo stash apply
git -C /app/repo add -A
git -C /app/repo commit -qm "recover lost aurora work"

# ---- 3) isolated per-branch deployment
git -C /app/repo archive feature-aurora | tar -x -C /app/deploy/aurora
git -C /app/repo archive feature-marble | tar -x -C /app/deploy/marble

# ---- 4) sanitize the CI workflow (standalone copy + in-repo copy)
python3 /app/bin/sanitize.py /app/ci.yml /app/ci.yml.new && mv /app/ci.yml.new /app/ci.yml
python3 /app/bin/sanitize.py /app/repo/.github/workflows/deploy.yml /app/deploy.yml.new \
  && mv /app/deploy.yml.new /app/repo/.github/workflows/deploy.yml
git -C /app/repo add .github/workflows/deploy.yml
git -C /app/repo commit -qm "sanitize ci workflow" 2>/dev/null || true

# ---- 5) SSH-served bare remote for user gitops
if ! id gitops >/dev/null 2>&1; then
  useradd -m -s /bin/bash gitops
fi
# useradd leaves the account locked (`!` in shadow/passwd); unlock it so sshd allows login.
# (Passwords are still unusable: PasswordAuthentication is disabled in sshd_config.)
echo 'gitops:atlas-deploy-pass' | chpasswd
mkdir -p /home/gitops/.ssh /app/ssh
if [ ! -f /app/ssh/deploy_key ]; then
  ssh-keygen -t ed25519 -N "" -f /app/ssh/deploy_key -q
fi
cp /app/ssh/deploy_key.pub /home/gitops/.ssh/authorized_keys
chown -R gitops:gitops /home/gitops/.ssh
chmod 700 /home/gitops/.ssh
chmod 600 /home/gitops/.ssh/authorized_keys

if [ ! -d /srv/git/atlas.git ]; then
  mkdir -p /srv/git
  git init --bare -q /srv/git/atlas.git
fi
chown -R gitops:gitops /srv/git/atlas.git

# sshd config + host keys + start daemon
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config <<'SSH'
Port 22
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM no
StrictModes no
ChallengeResponseAuthentication no
Subsystem sftp internal-sftp
SSH
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1 || true

if ! pgrep -x sshd >/dev/null 2>&1; then
  /usr/sbin/sshd
fi

echo "solve complete"
git -C /app/repo branch
ls /app/deploy/aurora/src /app/deploy/marble/src