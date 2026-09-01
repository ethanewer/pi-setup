FROM bench-base:ubuntu-24.04

WORKDIR /app

# ---------------------------------------------------------------------------
# Build a git repository at /app/repo with:
#   C1  base commit
#   C2  "secret" commit (contains payload/token.dat) -- later made DANGLING
#   server branch (from C1) edits the SAME payload.conf -> merge conflict
# The secret commit is intentionally dropped via `git reset --hard` so it is
# only reachable through the reflog / unreachable-object scanner.
# ---------------------------------------------------------------------------
RUN apt-get install -y git >/dev/null 2>&1 || apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/repo && cd /app/repo && \
    git init -q -b main && \
    git config user.email "alice@bench.test" && \
    git config user.name "Alice" && \
    git config init.defaultBranch main && \
    git config commit.gpgsign false && \
    echo "priority=low" > payload.conf && \
    echo "shared readme" > README.md && \
    git add -A && git commit -q -m "base: baseline configuration" && \
    C1=$(git rev-parse HEAD) && \
    mkdir -p payload && \
    echo "TOKEN-X7Y9" > payload/token.dat && \
    echo "priority=high" > payload.conf && \
    git add -A && git commit -q -m "secret: recoverable token payload" && \
    git branch server "$C1" && \
    git checkout -q server && \
    echo "priority=mid" > payload.conf && \
    echo "server.lock=on" > server.lock && \
    git add -A && git commit -q -m "server: mid config and lock file" && \
    git checkout -q main && \
    git reset -q --hard "$C1" && \
    echo "priority=prod" > payload.conf && \
    echo "audit entry 2026-01-01" > audit.log && \
    git add -A && git commit -q -m "main: add audit log" && \
    echo "OK"

# Repo is available both where the git dir lives and where a worktree would be.
WORKDIR /app