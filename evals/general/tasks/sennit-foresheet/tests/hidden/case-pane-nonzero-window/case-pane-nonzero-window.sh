#!/bin/sh
# sennit-foresheet hidden case: malformed *pane* offsets on a window that is
# NOT the current window, driven both through has-session and through
# select-pane (the command a user would actually type).
#
# Upstream's own targets-panes.sh only exercises pane offsets against its
# session "p" window 0. This case uses session "alpha", window index 1 (the
# current window is moved away first), with a two-pane fixture, and checks
# that malformed +N/-N pane offsets are rejected while valid pane offsets
# still work.
#
# Exit 0 on a correct build, non-zero on the buggy build.
set -u

TMUX="${TMUX:-/app/src/tmux}"
SOCK="sennit-pw$$"
TM="$TMUX -L$SOCK -f/dev/null"

$TM kill-server 2>/dev/null

fail=0

expect_reject() # $1 expected error text, $2 target
{
	expected="$1"
	target="$2"
	out=$($TM has-session -t "$target" 2>&1)
	if [ $? -eq 0 ]; then
		echo "target '$target' resolved (expected failure)." >&2
		fail=1
	elif [ "$out" != "$expected" ]; then
		echo "wrong error for target '$target'." >&2
		echo "expected: '$expected'" >&2
		echo "but got:  '$out'" >&2
		fail=1
	fi
}

# fixture: session alpha; window 0, then window 1 with two panes
$TM new-session -d -s alpha -x 80 -y 24 >/dev/null 2>&1
$TM new-window -t alpha >/dev/null 2>&1
$TM split-window -h -t alpha:1 >/dev/null 2>&1
$TM select-window -t alpha:0 >/dev/null 2>&1   # current window is now 0

# malformed pane offsets apply to window 1, not the current window
expect_reject "can't find pane: +0" "alpha:1.+0"
expect_reject "can't find pane: +foo" "alpha:1.+foo"
expect_reject "can't find pane: -0" "alpha:1.-0"

# literals the upstream tests never use: leading-zero number, stray letter
# and pane-side integer overflow all hit the same offset parser
expect_reject "can't find pane: +00" "alpha:1.+00"
expect_reject "can't find pane: +x" "alpha:1.+x"
expect_reject "can't find pane: +99999999999999999999999999" "alpha:1.+99999999999999999999999999"

# same through select-pane, which is the command that misled the user
if $TM select-pane -t "alpha:1.+foo" >/dev/null 2>&1; then
	echo "select-pane -t 'alpha:1.+foo' was silently accepted." >&2
	fail=1
fi
if $TM select-pane -t "alpha:1.+0" >/dev/null 2>&1; then
	echo "select-pane -t 'alpha:1.+0' was silently accepted." >&2
	fail=1
fi

# valid pane offset (next pane) must keep working
if ! $TM select-pane -t "alpha:1.+" >/dev/null 2>&1; then
	echo "valid 'alpha:1.+' (next pane) was rejected (over-correction)." >&2
	fail=1
fi

$TM kill-server 2>/dev/null

[ "$fail" = 1 ] && exit 1
exit 0