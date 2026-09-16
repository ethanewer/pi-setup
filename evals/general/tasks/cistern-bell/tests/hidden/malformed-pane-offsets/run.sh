#!/bin/sh
# Hidden case: malformed relative PANE offsets in target strings, with token
# shapes the upstream regress checks do not use (+2x, -0x, an overflowing
# number, +1.0), plus positive guards proving valid pane offsets (+, -,
# +01, +3 with wrap) still resolve against a 2x2 split.

PATH=/bin:/usr/bin
TERM=screen

[ -n "$TEST_TMUX" ] || exit 2
TMUX="$TEST_TMUX -LtestH2$$ -f/dev/null"
$TMUX kill-server 2>/dev/null

fail()
{
	echo "hidden-pane-offsets: $*" >&2
	$TMUX kill-server 2>/dev/null
	exit 1
}

# check $target $expected_pane_index
check()
{
	out=$($TMUX display-message -p -t "$1" '#{pane_index}' 2>&1)
	[ "$out" = "$2" ] || fail "target '$1' resolved to pane '$out', expected '$2'"
}

# check_fail $expected_error $target  (must not resolve, exact error text)
check_fail()
{
	out=$($TMUX has-session -t "$2" 2>&1)
	if [ $? -eq 0 ]; then
		fail "target '$2' silently resolved, expected failure"
	fi
	[ "$out" = "$1" ] || fail "target '$2' gave error '$out', expected '$1'"
}

# --- fixture: session p with a deterministic 2x2 split + a single-pane window
$TMUX new-session -d -s p -x 80 -y 24 || fail "cannot create session"
$TMUX split-window -h -t p:0       || fail "split failed"
$TMUX split-window -v -t p:0.%0    || fail "split failed"
$TMUX split-window -v -t p:0.%1    || fail "split failed"
$TMUX new-window -d -t p: -n solo  || fail "new-window failed"
$TMUX select-window -t p:0         || fail "select-window failed"

# --- malformed pane offsets must be rejected with the token in the error ----
check_fail "can't find pane: +2x" "p:0.+2x"
check_fail "can't find pane: -0x" "p:0.-0x"
check_fail "can't find pane: +99999999999999999999" "p:0.+99999999999999999999"
check_fail "can't find pane: +1.0" "p:0.+1.0"

# --- valid pane offsets keep working (regression guards) --------------------
$TMUX select-pane -t p:0.%0 || fail "select-pane failed"	# active pane is %0
check "p:0.+" "1"			# next pane
check "p:0.-" "3"			# previous pane, wraps
check "p:0.+01" "1"			# leading zeros still parse
check "p:0.+3" "3"			# forward three, wraps to %3
check "p:0.-1" "3"			# one back from %0 wraps to %3

$TMUX kill-server 2>/dev/null
echo "hidden-pane-offsets: PASS"
exit 0