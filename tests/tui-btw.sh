#!/usr/bin/env bash
# Drives the installed setup through a real TUI in tmux to test /btw, which has behaviour
# no print-mode run can reach: the full-screen side view, that the main thread is hidden
# while it is open and still running behind it, and escape returning to it.
#
#   tests/tui-btw.sh
#
# Requires tmux. Costs a few cents in model calls. Exits non-zero if any check fails.
set -uo pipefail

command -v tmux >/dev/null 2>&1 || { echo "tui-btw.sh: tmux is required" >&2; exit 2; }
# python3 is a stub on a clean macOS that prompts for the Xcode tools, so check it runs
# rather than that it exists — the session-file assertion at the end needs it.
python3 -c '' >/dev/null 2>&1 || { echo "tui-btw.sh: a working python3 is required (macOS: xcode-select --install)" >&2; exit 2; }

SESSION="pi-setup-tui-btw"
WORK="$(mktemp -d)"
LOG="$(mktemp)"
PASS=0; FAIL=0
printf 'export const GREETING = "hello-from-alpha";\n' > "$WORK/alpha.ts"
cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null; rm -rf "$WORK" "$LOG"; }
trap cleanup EXIT

tmux kill-session -t "$SESSION" 2>/dev/null
tmux new-session -d -s "$SESSION" -x 170 -y 45 "cd $WORK && pi 2>$LOG"

pane() { tmux capture-pane -p -t "$SESSION" -S -600 2>/dev/null; }
screen() { tmux capture-pane -p -t "$SESSION" 2>/dev/null; }
# The transcript echoes the question, so a token the test types appears once before the
# model has answered anything. Wait for the second occurrence unless told otherwise.
# Counts come from the visible screen: the side view covers it completely, and while it is
# up there is nothing else to match against.
wait_for() { # wait_for <text> [seconds] [min-count]
  local text="$1" limit="${2:-180}" want="${3:-2}" i=0
  while (( i < limit )); do
    [[ "$(screen | grep -cF "$text")" -ge "$want" ]] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}
# Retry a check against the top line: a single sample can catch a half-painted frame.
wait_line1() { # wait_line1 <text> [seconds]
  local text="$1" limit="${2:-15}" i=0
  while (( i < limit )); do
    screen | head -1 | grep -qF "$text" && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}
# Wait for the side view to stop answering, so a later keystroke is not raced.
wait_idle() { local i=0; while (( i < 200 )); do screen | grep -q "answering" || return 0; sleep 1; i=$((i+1)); done; return 1; }
check() { if [[ "$2" == "0" ]]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; fi }
send() { tmux send-keys -t "$SESSION" -l "$1"; sleep 0.4; tmux send-keys -t "$SESSION" Enter; }

sleep 10
printf '\nStartup\n'
pane | sed -n '/\[Extensions\]/,+1p'
pane | grep -q "btw"; check "btw is loaded" $?

printf '\nMain thread\n'
send "The codeword is ZEPHYR-9137. Reply with exactly ACK."
wait_for "ACK" 180 1; check "main thread answered" $?
sleep 2

printf '\nThe side view takes over the screen\n'
send "/btw What is the codeword? Reply with just it."
# The question does not contain the codeword, so one occurrence on screen is the answer,
# and it can only have come from the inherited history.
wait_for "ZEPHYR-9137" 180 1; check "side answer, with inherited history" $?
wait_line1 "main thread:"; check "header shows the side conversation" $?
# The defining property: the main thread's transcript is not on screen at all.
screen | grep -q "Reply with exactly ACK"; [[ $? == 1 ]]; check "main transcript is hidden" $?
screen | grep -q "esc return to the main thread"; check "footer shows the way out" $?

printf '\nMulti-turn inside the view\n'
send "Read alpha.ts and reply with only the string literal it assigns, nothing else."
wait_for "hello-from-alpha" 180 1; check "follow-up answered, with tools" $?
wait_idle; check "the view reports itself idle when done" $?

printf '\nEscape returns to the main thread\n'
tmux send-keys -t "$SESSION" Escape; sleep 3
screen | grep -q "Reply with exactly ACK"; check "main transcript is back" $?
screen | grep -q "side conversation"; [[ $? == 1 ]]; check "side view is gone" $?

printf '\nThe main thread keeps running while the view is open\n'
send "Run the bash command 'sleep 40; echo DONE-MAIN' and then reply with its output."
sleep 10
send "/btw Reply with exactly SIDE-DURING and nothing else."
# Question and answer both carry the token here, so two lines means it was answered.
wait_for "SIDE-DURING" 200 2; check "side answered during the main turn" $?
wait_line1 "main thread: working"; check "header reports the main thread running" $?
tmux send-keys -t "$SESSION" Escape; sleep 3
wait_for "DONE-MAIN" 240 2; check "main turn completed behind the view" $?

printf '\nCtrl+C belongs to Pi and must not leave or break the view\n'
send "/btw hi"
sleep 6
tmux send-keys -t "$SESSION" C-c; sleep 3
screen | grep -q "esc return to the main thread"; check "ctrl+c left the view open" $?
tmux send-keys -t "$SESSION" Escape; sleep 3
send "Reply with exactly STILL-ALIVE."
wait_for "STILL-ALIVE" 180 2; check "pi is healthy afterwards" $?

printf '\nSession file: nothing from the side thread may reach the main context\n'
tmux send-keys -t "$SESSION" -l "/exit"; sleep 0.3; tmux send-keys -t "$SESSION" Enter
sleep 6
python3 - <<'PY'
import glob, json, os
root = os.path.expanduser("~/.pi/agent/sessions")
files = sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True), key=os.path.getmtime)
if not files:
    print("  no session file found"); raise SystemExit(0)
messages = []
for line in open(files[-1]):
    entry = json.loads(line)
    if entry.get("type") == "message":
        messages.append(json.dumps(entry.get("message", {}).get("content")))
blob = json.dumps(messages)
leaked = [t for t in ("SIDE-DURING", "hello-from-alpha", "What is the codeword") if t in blob]
print("  side content found in main-thread messages:", leaked or "none")
raise SystemExit(1 if leaked else 0)
PY
check "no side content in the main context" $?

printf '\nExtension errors on stderr\n'
grep -i "error\|cannot find\|failed to load" "$LOG" | head -5 || true

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" == "0" ]]
