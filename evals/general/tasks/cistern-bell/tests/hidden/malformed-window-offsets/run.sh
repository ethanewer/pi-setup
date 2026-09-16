#!/bin/sh
# Hidden case: malformed relative WINDOW offsets in target strings, with
# token shapes the upstream regress checks do not use (+1x, +1.5, an
# overflowing number, -foo0), plus positive guards proving valid offsets
# (+, -, +01, -1 and the new-window index path +07) still resolve.

PATH=/bin:/usr/bin
TERM=screen

[ -n "$TEST_TMUX" ] || exit 2
TMUX="$TEST_TMUX -LtestH1$$ -f/dev/null"
$TMUX kill-server 2>/dev/null

fail()
{
	echo "hidden-window-offsets: $*" >&2
	$TMUX kill-server 2>/dev/null
	exit 1
}

# check $target $expected_window_index
check()
{
	out=$($TMUX display-message -p -t "$1" '#{window_index}' 2>&1)
	[ "$out" = "$2" ] || fail "target '$1' resolved to '$out', expected window index '$2'"
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

# --- fixture: session alpha, four named windows, current window is 0, last 2
$TMUX new-session -d -s alpha -x 80 -y 24 || fail "cannot create session"
$TMUX rename-window -t alpha:0 editor  || fail "rename failed"
$TMUX new-window -d -t alpha: -n editing || fail "new-window failed"
$TMUX new-window -d -t alpha: -n shell   || fail "new-window failed"
$TMUX new-window -d -t alpha: -n logs    || fail "new-window failed"
$TMUX select-window -t alpha:2 || fail "select-window failed"
$TMUX select-window -t alpha:0 || fail "select-window failed"

# --- malformed offsets must be rejected with the token in the error --------
check_fail "can't find window: +1x" "alpha:+1x"
check_fail "can't find window: +x2" "alpha:+x2"
check_fail "can't find window: +99999999999999999999" "alpha:+99999999999999999999"
check_fail "can't find window: -foo0" "alpha:-foo0"

# --- valid offsets keep working (regression guards) -------------------------
check "alpha:+" "1"		# next
check "alpha:-" "3"		# previous, wraps
check "alpha:+01" "1"		# leading zeros still parse
check "alpha:-1" "3"		# wraps

# --- the CMD_FIND_WINDOW_INDEX path (new-window -t) gets the same error -----
out=$($TMUX new-window -d -t 'alpha:+1x' 2>&1)
if [ $? -eq 0 ]; then
	fail "new-window -t 'alpha:+1x' succeeded (expected failure)"
fi
[ "$out" = "can't find window: +1x" ] || fail "new-window -t 'alpha:+1x' gave '$out'"
$TMUX new-window -d -t 'alpha:+07' -n offwin || fail "new-window -t 'alpha:+07' failed"
check "alpha:7" "7"
check "alpha:offwin" "7"
$TMUX kill-window -t alpha:7 || fail "cannot kill window 7"

$TMUX kill-server 2>/dev/null
echo "hidden-window-offsets: PASS"
exit 0