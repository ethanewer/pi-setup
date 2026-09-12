#!/bin/bash
# Oracle for cistern-bell: fix the real bug in the real tmux tree and rebuild.
#
# The malformed-offset bug is in cmd-find.c: two sites parse a relative window
# (and pane) offset with strtonum(window + 1, 1, INT_MAX, NULL), discarding
# the error result, so any unparseable offset silently becomes 0 and the
# target resolves to the current window/pane. The fix captures the error
# string and rejects the target when strtonum reported a problem.
set -euo pipefail

cd /app/tmux

# 1. Apply the fix (authored patch over the pinned parent tree).
git apply /solution/fix.patch

# 2. Rebuild incrementally. cmd-find.o and the link are all that change.
make -j1

# 3. The rebuilt binary is the deliverable.
test -x /app/tmux/tmux
echo "deliverable /app/tmux/tmux rebuilt from the repaired /app/tmux tree"

# 4. Sanity: the project's own target-resolution regress scripts must pass
#    against the rebuilt binary, and the previously-silent malformed offsets
#    must now error.
cd /app/tmux/regress
TEST_TMUX=/app/tmux/tmux sh targets.sh
TEST_TMUX=/app/tmux/tmux sh targets-panes.sh
echo "all target-resolution regress tests pass"