#!/usr/bin/env bash
# promote.sh -- publish local main into a shared remote main, preserving work.
#
# The shared remote's main has diverged from this clone's main: a teammate's
# in-progress branch sits on it by mistake, so an ordinary push is rejected as
# non-fast-forward. The safe resolution is to integrate the remote's diverged
# history into the local main line and then push with an ordinary (fast
# forward) update. Every existing commit keeps its identity and stays
# reachable: no history is rewritten, nothing is orphaned.
#
# Usage: bash promote.sh <workspace> <remote-path>
#   <workspace>    a git working clone whose branch `main` has the finished
#                  work to publish
#   <remote-path>  path of the bare shared remote to publish into
set -euo pipefail

ws=$1
remote=$2
cd "$ws"

# freshen the remote-tracking ref from the shared remote main
git fetch "$remote" 'refs/heads/main:refs/remotes/origin/main'

# integrate the remote main history (default merge strategy; never opens an
# editor). In these repositories the two lines touch disjoint files, so the
# merge is clean.
git merge --no-edit refs/remotes/origin/main

# publish: the merge makes this a plain fast-forward update, no force needed
git push "$remote" 'HEAD:refs/heads/main'

echo "promoted $ws -> $remote"