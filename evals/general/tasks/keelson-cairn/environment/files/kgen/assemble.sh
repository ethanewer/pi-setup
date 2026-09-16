#!/usr/bin/env bash
# Assembles the checked-in kedd tree at DEST as a git repository with an
# incremental, dated commit history - the way the real project would have
# grown. Run once at image build time; the assembled repository is what the
# operators (and the eval agent) inspect with `git log` / `git blame`.
#
# Usage: assemble.sh <SRC> <DEST>
set -euo pipefail

SRC=$1
DEST=$2

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC/." "$DEST/"

cd "$DEST"
git init -q -b main
git config --system --add safe.directory '*' 2>/dev/null || true
git config --system user.email "build@localhost"
git config --system user.name "build"

export GIT_AUTHOR_NAME="Voss Estrat"
export GIT_AUTHOR_EMAIL="voss.estrat@cairn-marine.local"
export GIT_COMMITTER_NAME="Voss Estrat"
export GIT_COMMITTER_EMAIL="voss.estrat@cairn-marine.local"

commit() {
    local msg=$1
    local date=$2
    shift 2
    git add -- "$@"
    GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git commit -q -m "$msg"
}

commit "Initial project scaffold: build, launch, and docs" \
    "2026-05-11T09:14:00+00:00" \
    README.md build.sh run.sh .gitignore

commit "Event model, workload parser, and digest helper" \
    "2026-05-12T10:02:00+00:00" \
    src/cairn/Event.java src/cairn/Workload.java src/cairn/Digest.java \
    tools/gen_workloads.py workloads/sample/workload.txt

commit "Durable ordered journal writer" \
    "2026-05-13T08:47:00+00:00" \
    src/cairn/Journal.java

commit "Worker pool and heartbeat ticker" \
    "2026-05-14T11:31:00+00:00" \
    src/cairn/WorkerPool.java src/cairn/Ticker.java

commit "Daemon main plus termination wiring; semantic check suite" \
    "2026-05-15T09:52:00+00:00" \
    src/cairn/Keddaemon.java src/cairn/ShutdownHook.java src/cairn/Check.java \
    tests/check.sh

echo "kedd: assembled $DEST with $(git rev-list --count HEAD) commits:"
git log --oneline