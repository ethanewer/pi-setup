#!/bin/sh
# h1: the FIFO-lagging client and a healthy client attach to a session whose
# only pane is SILENT; the lag builds up on a SECOND window created later
# (100x30, 0.02s tick, 32-char lines, sessions 'home'/'away'). The moves and
# respawn then stress the pane that the clients have fallen behind on.
# Inputs deliberately differ from the upstream regression (silent origin
# pane, different sizes/rates/timings/names).
PATH=/bin:/usr/bin
TERM=screen
[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest -f/dev/null"
$TMUX kill-server 2>/dev/null
DIR=$(mktemp -d)
FIFO=$DIR/fifo
SERVER=
mkfifo "$FIFO" || exit 1
cleanup() {
	[ -n "$SERVER" ] && kill -9 "$SERVER" 2>/dev/null
	$TMUX kill-server 2>/dev/null
	exec 8<&- 2>/dev/null
	rm -rf "$DIR"
}
trap cleanup 0 1 15
alive() {
	if ! kill -0 "$SERVER" 2>/dev/null; then
		SERVER=
		echo "server died after $1"
		exit 1
	fi
	$TMUX has -t home || exit 1
}
wait_clients() {
	n=0
	while [ $n -lt 50 ]; do
		[ "$($TMUX lsc 2>/dev/null | wc -l)" -ge $1 ] && return
		sleep 0.1
		n=$((n + 1))
	done
	echo "control clients did not attach"; exit 1
}
$TMUX new -d -x 100 -y 30 -s home 'sleep 90' || exit 1
SERVER=$($TMUX display -pt home '#{pid}')
( sleep 60 ) | $TMUX -C attach -t home >"$FIFO" 2>&1 &
exec 8<"$FIFO"
( sleep 60 ) | $TMUX -C attach -t home >/dev/null 2>&1 &
wait_clients 2
$TMUX neww -d -t home 'while :; do echo HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH; sleep 0.02; done' || exit 1
sleep 2
$TMUX new -d -s away || exit 1
$TMUX movew -d -s home:1 -t away: || exit 1
sleep 1
OLD_PID=$($TMUX display -pt away:1 '#{pane_pid}' 2>/dev/null) || exit 1
$TMUX respawn-pane -k -t away:1 'echo resurrected; sleep 60' || exit 1
sleep 1
alive "respawn of a moved silent-session pane"
NEW_PID=$($TMUX display -pt away:1 '#{pane_pid}' 2>/dev/null) || exit 1
[ -n "$OLD_PID" ] && [ "$OLD_PID" != "$NEW_PID" ] || {
	echo "HIDDEN CASE h1: respawn did not take effect" >&2
	exit 1
}
echo "HIDDEN CASE h1: ok"
exit 0