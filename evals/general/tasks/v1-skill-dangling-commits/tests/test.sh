#!/bin/bash
# Verifier: independently locate the dangling secret.txt content in /app/repo
# (via reflog + fsck) and compare against /app/recovered.txt.
mkdir -p /logs/verifier
reward=0
if [ -f /app/recovered.txt ]; then
  expected=$(python3 - <<'PYEOF'
import subprocess
repo = "/app/repo"
def run(args):
    return subprocess.run(args, capture_output=True, text=True, cwd=repo)
ids = sorted({t.split()[0] for t in run(["git", "reflog", "--all"]).stdout.splitlines() if t.split()})
# also consider unreachable commits found via fsck (belt and suspenders)
if run(["git", "fsck", "--unreachable"]).returncode == 0:
    for line in run(["git", "fsck", "--unreachable"]).stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "unreachable" and parts[1] == "commit":
            ids.append(parts[2])
expected = ""
for i in sorted(set(ids)):
    if run(["git", "cat-file", "-e", i + "^{commit}"]).returncode != 0:
        continue
    r = run(["git", "show", i + ":secret.txt"])
    if r.returncode == 0 and r.stdout.strip():
        expected = r.stdout.rstrip("\n")
        break
print(expected)
PYEOF
  )
  got=$(cat /app/recovered.txt | tr -d '\r')
  got=$(echo "$got" | sed 's/[[:space:]]*$//')
  if [ -n "$expected" ] && [ "$got" = "$expected" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt