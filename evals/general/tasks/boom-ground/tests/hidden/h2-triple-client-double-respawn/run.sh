#!/bin/sh
# h2: THREE control clients (two healthy, one on the unread fifo), 40x25
# windows, 48-char lines at 0.05s on the origin pane, the moved pane ticking
# at 0.015s; the moved pane is respawned TWICE. Inputs the upstream test does
# not use: third client, double respawn, different geometry and rates.
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
	$TMUX has -t alpha || exit 1
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
$TMUX new -d -x 40 -y 25 -s alpha 'while :; do echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; sleep 0.05; done' || exit 1
SERVER=$($TMUX display -pt alpha '#{pid}')
( sleep 60 ) | $TMUX -C attach -t alpha >"$FIFO" 2>&1 &
exec 8<"$FIFO"
( sleep 60 ) | $TMUX -C attach -t alpha >/dev/null 2>&1 &
( sleep 60 ) | $TMUX -C attach -t alpha >/dev/null 2>&1 &
wait_clients 3
sleep 3
$TMUX neww -d -t alpha 'while :; do echo BBBBBBBBBBBBBBBBB; sleep 0.015; done' || exit 1
sleep 1
$TMUX new -d -s beta || exit 1
$TMUX movew -d -s alpha:1 -t beta: || exit 1
sleep 2
$TMUX respawn-pane -k -t beta:1 'echo b1; sleep 60' || exit 1
sleep 1
$TMUX respawn-pane -k -t beta:1 'echo b2; sleep 60' || exit 1
sleep 1
alive "double respawn of a moved pane with three clients"
echo "HIDDEN CASE h2: ok"
exit 0