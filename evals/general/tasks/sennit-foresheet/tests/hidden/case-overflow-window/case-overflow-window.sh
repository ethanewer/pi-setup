#!/bin/sh
# sennit-foresheet hidden case: malformed *numeric* window offsets that
# overflow the parser's integer range.
#
# Upstream's own regression tests only use tiny malformed offsets (+0, +foo,
# -0, -foo). This case drives 29-digit numeric offsets through the same
# cmd-find offset code: strtonum() overflows, and the buggy build silently
# clamps and applies the offset (the target "resolves"); a correct build
# must reject the target with "can't find window: <target>".
#
# Exit 0 on a correct build, non-zero on the buggy build.
set -u

TMUX="${TMUX:-/app/src/tmux}"
SOCK="sennit-ow$$"
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

# fixture: session alpha with several windows
$TM new-session -d -s alpha -x 80 -y 24 >/dev/null 2>&1
$TM new-window -t alpha >/dev/null 2>&1
$TM new-window -t alpha >/dev/null 2>&1

# 29 decimal digits: always an overflow, for either sign
expect_reject "can't find window: +99999999999999999999999999999" \
    "alpha:+99999999999999999999999999999"
expect_reject "can't find window: -99999999999999999999999999999" \
    "alpha:-99999999999999999999999999999"

# mixed digits too (leading digit differs from the golden tests' inputs)
expect_reject "can't find window: +10000000000000000000000000000" \
    "alpha:+10000000000000000000000000000"

# a valid small offset must keep working: the fix must not over-correct
if ! $TM has-session -t "alpha:+1" >/dev/null 2>&1; then
	echo "valid +1 offset was rejected (over-correction)." >&2
	fail=1
fi

$TM kill-server 2>/dev/null

[ "$fail" = 1 ] && exit 1
exit 0