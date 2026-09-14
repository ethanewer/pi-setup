#!/bin/sh
# Reproduction for the sennit-foresheet bug: malformed session-relative
# +N/-N window and pane offsets are silently accepted instead of rejected.
#
# Contract (see instruction.md): the binary under test comes from $TMUX
# (default /app/src/tmux). The script starts a throwaway server on a /tmp
# socket and drives strictly-resolving, target-aware commands with malformed
# session-relative offset targets. It exits 0 iff every such target is
# rejected with the correct "can't find window:"/"can't find pane:" error,
# and exits non-zero (printing a one-line diagnostic per failure to stderr)
# iff any malformed target is silently accepted -- which is the bug.
set -u

TMUX="${TMUX:-/app/src/tmux}"
SOCK="sennit-r$$"
TM="$TMUX -L$SOCK -f/dev/null"

$TM kill-server 2>/dev/null

fail=0

expect_reject() # $1 expected error text, $2 target
{
	expected="$1"
	target="$2"
	out=$($TM has-session -t "$target" 2>&1)
	if [ $? -eq 0 ]; then
		echo "BUG: target '$target' was silently accepted (no error)." >&2
		fail=1
	elif [ "$out" != "$expected" ]; then
		echo "BUG: target '$target' gave the wrong error." >&2
		echo "     expected: '$expected'" >&2
		echo "     got:      '$out'" >&2
		fail=1
	fi
}

# fixture: session alpha, window 0; window 1 with two panes
$TM new-session -d -s alpha -x 80 -y 24 >/dev/null 2>&1
$TM new-window -t alpha >/dev/null 2>&1
$TM split-window -h -t alpha:1 >/dev/null 2>&1

# malformed window offsets (bug: silently resolve instead of failing)
expect_reject "can't find window: +0" "alpha:+0"
expect_reject "can't find window: +foo" "alpha:+foo"
expect_reject "can't find window: -0" "alpha:-0"

# malformed pane offset on window 1 (bug: silently resolves too)
expect_reject "can't find pane: +0" "alpha:1.+0"

$TM kill-server 2>/dev/null

[ "$fail" = 1 ] && exit 1
exit 0