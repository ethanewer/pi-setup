#!/bin/bash
# boom-ground oracle: apply the upstream fix, rebuild, write the reproduction
# deliverable, and prove both directions (repro fails on the pristine buggy
# build, passes on the repaired build).
set -euo pipefail

cd /app/src

# 1. the fix: reset control-mode offsets on pane respawn (control.c, spawn.c,
#    tmux.h). Patch obtained from the upstream fix commit; applies cleanly to
#    the base commit.
git apply /solution/fix.patch

# 2. rebuild in place (the project is already configured).
make -j2

# 3. the deliverable reproduction script.
cat > /app/repro.sh <<'REPRO'
#!/bin/sh
# Repro for boom-ground: respawn a moved pane while a control-mode client is
# behind on it; the server must survive. Exits 0 iff the server survived and
# responded; non-zero with a diagnostic otherwise.
#
# Honours TEST_TMUX (tmux binary to test), defaulting to /app/src/tmux.
PATH=/bin:/usr/bin
TERM=screen
[ -z "$TEST_TMUX" ] && TEST_TMUX=/app/src/tmux
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
		echo "repro: server process died after $1" >&2
		exit 1
	fi
	$TMUX has -t home >/dev/null 2>&1 || {
		echo "repro: server not answering after $1" >&2
		exit 1
	}
}
# Origin session: silent pane, so any backlog on the control clients builds up
# on the pane created below (which is the one respawned later).
$TMUX new -d -x 100 -y 30 -s home 'sleep 90' || exit 1
SERVER=$($TMUX display -pt home '#{pid}')
# One control client whose output goes into a fifo nobody reads, and one
# healthy client that keeps the pane's output moving.
( sleep 60 ) | $TMUX -C attach -t home >"$FIFO" 2>&1 &
exec 8<"$FIFO"
( sleep 60 ) | $TMUX -C attach -t home >/dev/null 2>&1 &
n=0
while [ $n -lt 50 ]; do
	[ "$($TMUX lsc 2>/dev/null | wc -l)" -ge 2 ] && break
	sleep 0.1
	n=$((n + 1))
done
# A writing pane that both clients fall behind on.
$TMUX neww -d -t home 'while :; do echo HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH; sleep 0.02; done' || exit 1
sleep 2
# Move that window out of the clients' session, then respawn it.
$TMUX new -d -s away || exit 1
$TMUX movew -d -s home:1 -t away: || exit 1
sleep 1
$TMUX respawn-pane -k -t away:1 'echo resurrected; sleep 60' || exit 1
sleep 1
alive "the respawn"
exit 0
REPRO
chmod +x /app/repro.sh

# 4. prove both directions, the way the verifier will.
if TEST_TMUX=/opt/prefix/tmux sh /app/repro.sh >/tmp/probe-buggy.out 2>&1; then
	echo "BOOM-GROUND ORACLE ERROR: reproduction passed on the buggy build" >&2
	exit 1
fi
echo "repro fails on the buggy build as expected: $(tail -1 /tmp/probe-buggy.out)"

if ! TEST_TMUX=/app/src/tmux sh /app/repro.sh >/tmp/probe-fixed.out 2>&1; then
	echo "BOOM-GROUND ORACLE ERROR: reproduction failed on the repaired build" >&2
	tail -5 /tmp/probe-fixed.out >&2
	exit 1
fi
echo "repro passes on the repaired build"

echo "boom-ground oracle: done"
exit 0