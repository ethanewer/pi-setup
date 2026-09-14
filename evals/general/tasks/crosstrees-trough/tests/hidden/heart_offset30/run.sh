#!/bin/sh
# hidden case h2: variation-selector-widened glyph (heart U+2764 + VS16) at the
# START of line 2 in the right pane of a 2-pane split in a 60-col window
# (xoff=30). Base glyph is the first cell of the pane line.
BIN=$1
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "usage: run.sh <tmux-binary>" >&2; exit 2; }
PATH=/bin:/usr/bin
TERM=screen
LC_ALL=C.UTF-8
export TERM LC_ALL
TMUX="$BIN -Lh2$$ -f/dev/null"
TMP=$(mktemp)
trap "rm -f $TMP; $TMUX kill-server 2>/dev/null" 0 1 15
$TMUX kill-server 2>/dev/null
$TMUX new -d -x60 -y6 -s test || exit 1
$TMUX set -g status off || exit 1
$TMUX set -s variation-selector-always-wide on || exit 1
WINDOW=$($TMUX neww -dPF '#{window_id}' "exec sleep 100") || exit 1
PANE=$($TMUX splitw -dhPF '#{pane_id}' -t "$WINDOW" "exec sleep 100") || exit 1
$TMUX selectw -t "$WINDOW" || exit 1
$TMUX respawnp -k -t "$PANE" "printf 'W\n\342\235\244\357\270\217ABCDEFGHIJKL\nV'; exec sleep 100" || exit 1
sleep 1
$TMUX capturep -p -t "$PANE" >$TMP || exit 1
want=$(printf '\342\235\244\357\270\217ABCDEFGHIJKL')
got=$(sed -n 2p $TMP)
[ "$got" = "$want" ] || { echo "line 2: expected '$want', got '$got'" >&2; exit 1; }
echo "hidden h2 ok"
exit 0
