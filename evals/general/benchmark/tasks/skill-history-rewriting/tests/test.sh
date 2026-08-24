#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -d /app/repo/.git ]; then
  python3 - <<'PYEOF'
import subprocess, sys, os
repo = "/app/repo"
def run(args):
    return subprocess.run(args, capture_output=True, text=True, cwd=repo)
commits = run(["git","log","--format=%H"]).stdout.split()
ok = bool(commits) and len(commits) >= 2
for c in commits:
    trees = run(["git","ls-tree","-r","--name-only",c]).stdout.split()
    if any(os.path.basename(p) == "secret.txt" for p in trees):
        ok = False
def head_file(p):
    r = run(["git","show",f"HEAD:{p}"])
    return r.stdout if r.returncode == 0 else None
if not (head_file("readme.md") == "main cfg\n"
        and head_file("seed.cfg") == "seed=1\n"
        and head_file("feature.txt") == "2.0\n"):
    ok = False
sys.exit(0 if ok else 1)
PYEOF
fi
echo "$reward" > /logs/verifier/reward.txt