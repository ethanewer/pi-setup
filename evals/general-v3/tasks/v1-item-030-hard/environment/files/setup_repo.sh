#!/bin/bash
# Build a git repository at /app/repo whose history is riddled with leaked
# credentials (AWS access key/secret, GitHub PAT / fine-grained token) spread
# over several commits, a tag, and (in hard mode) an extra branch and packfiles.
# MODE=main : 4 commits, refs: main, staging, tag v1.0, loose objects
# MODE=hard : 5 commits, refs: main, staging, tag v1.0, legacy/2023, packed
set -euo pipefail
MODE="${1:-main}"
REPO=/app/repo
rm -rf "$REPO"
mkdir -p "$REPO"
cd "$REPO"

git init -q -b main
git config user.email "dev@bench.test"
git config user.name "Dev Bench"
git config commit.gpgsign false

AWS_ID="AKIAEXAMPLEKEY000001"
AWS_SECRET="EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GH_PAT="ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"
GH_FINE="github_pat_EXAMPLE_EXAMPLE_EXAMPLE"

# C0: base scaffold
cat > README.md <<'EOF'
# bench repo
Inventory tracking plus deploy automation.
EOF
printf '*.log\n__pycache__/\n' > .gitignore
git add -A
git commit -q -m "chore: base scaffold"

# C1: deploy automation (leaks AWS + GitHub PAT in deploy.py)
cat > deploy.py <<'EOF'
import os
AWS_ACCESS_KEY_ID = "AKIAEXAMPLEKEY000001"
AWS_SECRET_ACCESS_KEY = "EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0"
GITHUB_TOKEN = "ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE"

def deploy():
    return os.environ.get("DEPLOY_TARGET", "staging")
EOF
git add -A
if [ "$MODE" = "hard" ]; then
  git commit -q -m "feat: deploy automation (key AKIAEXAMPLEKEY000001)"
else
  git commit -q -m "feat: deploy automation"
fi

# C2: inventory page (leaks AWS id + PAT again)
cat > inventory.html <<'EOF'
<html><body><h1>Inventory</h1>
<!-- CI access: AKIAEXAMPLEKEY000001 / ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE -->
<p>stock levels here</p></body></html>
EOF
git add -A
if [ "$MODE" = "hard" ]; then
  git commit -q -m "feat: inventory page (ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLE)"
else
  git commit -q -m "feat: inventory page"
fi

# C3: settings module (leaks AWS secret again at HEAD)
cat > config.py <<'EOF'
SETTINGS = {
    "aws_secret": "EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0",
}
EOF
git add -A
git commit -q -m "refactor: settings module"
C3=$(git rev-parse HEAD)

# extra refs
git branch staging "HEAD~1"
git tag -a v1.0 -m "release v1.0" "HEAD~2"

if [ "$MODE" = "hard" ]; then
  # extra legacy branch leaking a fine-grained GitHub token, incl. commit msg
  git checkout -q -b legacy/2023 "HEAD~3"
  cat > legacy.txt <<'EOF'
fine_grained = "github_pat_EXAMPLE_EXAMPLE_EXAMPLE"
EOF
  git add -A
  git commit -q -m "legacy: migration notes (github_pat_EXAMPLE_EXAMPLE_EXAMPLE)"
  git checkout -q main
  # pack all objects so they live in packfiles, not loose files
  git repack -adf -q
  # create reflog churn so old hashes are recorded (must be expired by agent)
  C3=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1
  git reset -q --hard "$C3"
fi

echo "repo built (mode=$MODE)"
git log --oneline --all | head -10
