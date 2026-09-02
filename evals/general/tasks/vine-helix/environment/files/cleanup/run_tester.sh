#!/usr/bin/env bash
#
# vine-helix / cancellation grace tester.
#
# Launches the cleanup worker as a background job, lets it start a bundle, then
# sends SIGTERM to cancel it, and verifies the worker still ran its cleanup
# (the "cleanup-complete" marker must appear in /app/cleanup/sweep.log before
# the process exited).
#
# Exit 0  => in-flight cleanup completed on cancellation.
# Exit 1  => the worker was killed without running its cleanup.
set -u
LOG=/app/cleanup/sweep.log
rm -f "$LOG"

python3 /app/cleanup/sweep.py &
pid=$!
sleep 0.8
kill -TERM "$pid" 2>/dev/null
# give the worker a beat to finish its in-flight bundle + cleanup before verdict
sleep 1.0
if kill -0 "$pid" 2>/dev/null; then
  kill -KILL "$pid" 2>/dev/null
  echo "cancel-test: worker still alive after signal (hung)" >&2
  exit 1
fi
if grep -q 'cleanup-complete' "$LOG"; then
  echo "cancel-test: in-flight cleanup completed after cancellation"
  exit 0
else
  echo "cancel-test: cleanup did not run before exit" >&2
  exit 1
fi