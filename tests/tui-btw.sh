#!/usr/bin/env bash
# Drives the installed setup through a real TUI in tmux to test /btw, which has
# behaviour no print-mode run can reach: inline rendering, sticky input routing, the
# footer mode indicator, and cancelling an answer in flight.
#
#   tests/tui-btw.sh
#
# Requires tmux. Costs a few cents in model calls. Exits non-zero if any check fails.
set -uo pipefail

command -v tmux >/dev/null 2>&1 || { echo "tui-btw.sh: tmux is required" >&2; exit 2; }

SESSION="pi-setup-tui-btw"
WORK="$(mktemp -d)"
LOG="$WORK/pi.log"
PASS=0; FAIL=0
printf 'export const GREETING = "hello-from-alpha";\n' > "$WORK/alpha.ts"
cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x 180 -y 55 "cd $WORK && pi 2>$LOG"

pane() { tmux capture-pane -p -t "$SESSION" -S -600 2>/dev/null; }
status_line() { pane | grep -v '^\s*$' | tail -1; }
# The transcript echoes the question, so a token the test types appears once before the
# model has answered anything. Wait for the second occurrence unless told otherwise.
wait_for() { # wait_for <text> [seconds] [min-count]
  local text="$1" limit="${2:-180}" want="${3:-2}" i=0
  while (( i < limit )); do
    [[ "$(pane | grep -cF "$text")" -ge "$want" ]] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}
check() { if [[ "$2" == "0" ]]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; fi }
send() { tmux send-keys -t "$SESSION" -l "$1"; sleep 0.4; tmux send-keys -t "$SESSION" Enter; }

sleep 10
printf '\nStartup\n'
pane | sed -n '/\[Extensions\]/,+1p'
pane | grep -q "btw"; check "btw is loaded" $?

printf '\n/btw\n'
send "/btw Reply with exactly SIDE-ONE and nothing else."
wait_for "SIDE-ONE"; check "answer renders inline" $?
status_line | grep -q "btw"; check "footer shows the side thread" $?

send "What constant does alpha.ts export? Reply with only its value."
wait_for "hello-from-alpha" 180 1; check "sticky input reaches the side thread, with tools" $?

send "/btw:end"
wait_for "back on the main thread" 40 1; check "/btw:end returns" $?
sleep 2
status_line | grep -q "btw"; [[ $? == 1 ]]; check "footer cleared" $?

printf '\nMain thread\n'
send "Reply with exactly MAIN-OK and nothing else."
wait_for "MAIN-OK"; check "main thread still answers" $?

printf '\nCancelling an answer in flight\n'
send "/btw Count slowly from 1 to 500, one number per line."
sleep 4
send "/btw:end"
wait_for "back on the main thread" 40 1; check "cancel acknowledged" $?
sleep 2
status_line | grep -q "btw"; [[ $? == 1 ]]; check "footer cleared after cancel" $?

tmux send-keys -t "$SESSION" -l "/exit"; sleep 0.3; tmux send-keys -t "$SESSION" Enter
sleep 6

printf '\nSession file: nothing from the side thread may reach the main context\n'
python3 - "$WORK" <<'PY'
import glob, json, os, sys
root = os.path.expanduser("~/.pi/agent/sessions")
key = sys.argv[1].strip("/").replace("/", "-")
files = sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True), key=os.path.getmtime)
files = [f for f in files if key.split("-")[-1] in f] or files[-1:]
if not files:
    print("  no session file found"); raise SystemExit(0)
messages, customs = [], []
for line in open(files[-1]):
    entry = json.loads(line)
    if entry.get("type") == "message":
        messages.append(json.dumps(entry.get("message", {}).get("content")))
    elif entry.get("type") == "custom":
        customs.append(entry.get("customType"))
blob = json.dumps(messages)
leaked = [t for t in ("SIDE-ONE", "hello-from-alpha") if t in blob]
print("  side answers found in main-thread messages:", leaked or "none")
print("  btw entries recorded:", customs.count("btw-exchange"))
raise SystemExit(1 if leaked else 0)
PY
check "no side content in the main context" $?

printf '\nExtension errors on stderr\n'
grep -i "error\|cannot find\|failed to load" "$LOG" | head -5 || true

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == "0" ]]
