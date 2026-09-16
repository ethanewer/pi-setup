#!/bin/bash
# Oracle for sennit-foresheet: tmux silently accepts malformed
# session-relative +N/-N window and pane offsets (GitHub issue #5576).
#
# Sequence mirrors the intended agent work:
#   1. write the reproduction deliverable (/app/repro.sh) BEFORE fixing;
#   2. apply the real upstream fix (cmd-find.c only -- the diff between the
#      pinned parent 73db0a54... and the master fix merge d44bfda2...);
#   3. rebuild with the project's own build;
#   4. prove the fix with the project's own regression tests.
set -euo pipefail

SRC=/app/src

# 1) reproduction deliverable
install -m 0755 /solution/repro-solution.sh /app/repro.sh

# sanity: the reproduction catches the bug on the UNFIXED build
if TMUX="$SRC/tmux" sh /app/repro.sh >/dev/null 2>&1; then
    echo "ORACLE ERROR: reproduction passed on the buggy build" >&2
    exit 1
fi

# 2) the fix: capture the strtonum error string for +N/-N offsets in
#    cmd_find_get_window_with_session / cmd_find_get_pane_with_window and
#    return failure (-1) when the number is not valid in [1, INT_MAX].
cd "$SRC"
git apply /solution/fix.patch

# 3) rebuild
make -j1

# 4) the project's own regression tests must pass on the fixed tree
(cd regress && TEST_TMUX="$PWD/../tmux" sh ./targets.sh)
(cd regress && TEST_TMUX="$PWD/../tmux" sh ./targets-panes.sh)

echo "ORACLE OK: fix applied, rebuilt, regression tests pass"
exit 0