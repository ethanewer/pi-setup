#!/usr/bin/env bash
# Oracle for thwart-lantern. Installs the real solver (/solution/promote.sh)
# under /app and applies it to all three scenarios. It does the actual work
# (fetch, integrate, publish) and never reads /tests.
set -euo pipefail

export GIT_AUTHOR_NAME="Dev Ops" GIT_AUTHOR_EMAIL="dev@ops.local"
export GIT_COMMITTER_NAME="Dev Ops" GIT_COMMITTER_EMAIL="dev@ops.local"

SOLVER_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SOLVER_DIR/promote.sh" /app/promote.sh
chmod +x /app/promote.sh

bash /app/promote.sh /app/workspace /app/remote/tally.git
bash /app/promote.sh /app/workspace-h1 /app/remote/stockpile.git
bash /app/promote.sh /app/workspace-h2 /app/remote/gatewatch.git

echo "oracle: hotfix published to all three shared remotes"