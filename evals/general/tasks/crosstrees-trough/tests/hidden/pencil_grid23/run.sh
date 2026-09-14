#!/bin/sh
# hidden case h3: variation-selector-widened glyph (pencil U+270F + VS16, same
# glyph as upstream test but DIFFERENT geometry): bottom-right pane of a 2x2
# grid (both xoff and yoff nonzero), glyph at column 3 of line 3. Exercises
# xoff+yoff together and a mid-line column the upstream test does not use.
BIN=$1
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "usage: run.sh <tmux-binary>" >&2; exit 2; }
PATH=/bin:/usr/bin
TERM=screen
LC_ALL=C.UTF-8
export TERM LC_ALL
TMUX="$BIN -Lh3$$ -f/dev/null"
TMP=$(mktemp)
trap "rm -f $TMP; $TMUX kill-server 2>/dev/null" 0 1 15
$TMUX kill-server 2>/dev/null
$TMUX new -d -x40 -y10 -s test || exit 1
$TMUX set -g status off || exit 1
$TMUX set -s variation-selector-always-wide on || exit 1
WINDOW=$($TMUX neww -dPF '#{window_id}' "exec sleep 100") || exit 1
PRIGHT=$($TMUX splitw -dhPF '#{pane_id}' -t "$WINDOW" "exec sleep 100") || exit 1
PBOT=$($TMUX splitw -dvPF '#{pane_id}' -t "$PRIGHT" "exec sleep 100") || exit 1
$TMUX selectw -t "$WINDOW" || exit 1
$TMUX respawnp -k -t "$PBOT" "printf 'A\nB\nCC\342\234\217\357\270\217D\nE'; exec sleep 100" || exit 1
sleep 1
$TMUX capturep -p -t "$PBOT" >$TMP || exit 1
want=$(printf 'CC\342\234\217\357\270\217D')
got=$(sed -n 3p $TMP)
[ "$got" = "$want" ] || { echo "line 3: expected '$want', got '$got'" >&2; exit 1; }
echo "hidden h3 ok"
exit 0