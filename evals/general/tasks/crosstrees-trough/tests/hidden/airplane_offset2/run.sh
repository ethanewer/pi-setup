#!/bin/sh
# hidden case h1: variation-selector-widened glyph (airplane U+2708 + VS16)
# in the RIGHT pane of a 2-pane horizontal split (xoff=10), glyph at pane
# column 1 of LINE 2. Different glyph from the upstream test (pencil).
BIN=$1
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "usage: run.sh <tmux-binary>" >&2; exit 2; }
PATH=/bin:/usr/bin
TERM=screen
LC_ALL=C.UTF-8
export TERM LC_ALL
TMUX="$BIN -Lh1$$ -f/dev/null"
TMP=$(mktemp)
trap "rm -f $TMP; $TMUX kill-server 2>/dev/null" 0 1 15
$TMUX kill-server 2>/dev/null
$TMUX new -d -x20 -y6 -s test || exit 1
$TMUX set -g status off || exit 1
$TMUX set -s variation-selector-always-wide on || exit 1
WINDOW=$($TMUX neww -dPF '#{window_id}' "exec sleep 100") || exit 1
PANE=$($TMUX splitw -dhPF '#{pane_id}' -t "$WINDOW" "exec sleep 100") || exit 1
$TMUX selectw -t "$WINDOW" || exit 1
$TMUX respawnp -k -t "$PANE" "printf 'Q\nX\342\234\210\357\270\217Y\nZ'; exec sleep 100" || exit 1
sleep 1
$TMUX capturep -p -t "$PANE" >$TMP || exit 1
want=$(printf 'X\342\234\210\357\270\217Y')
got=$(sed -n 2p $TMP)
[ "$got" = "$want" ] || { echo "line 2: expected '$want', got '$got'" >&2; exit 1; }
echo "hidden h1 ok"
exit 0
