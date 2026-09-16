#!/bin/bash
# Shared harness for the chainplate-foresheet hidden cases.
#
# Each hidden case reproduces the same bug scenario with different modes of
# the fd CLI: the search root is a symlink (`link`) inside a working directory
# that is REMOVED ~0.2 s after the fd process appears, while fd walks a large
# tree of files through that symlink with --full-path. With --full-path every
# match must be resolved against the process's current directory; once the
# cwd is gone that resolution fails, which (a) panics the whole process on
# the buggy tree (exit 101) and (b) is handled gracefully on a fixed tree,
# either by aborting the search and reporting the filesystem error
# (--show-errors, exit status 1 -- the upstream choice) or by completing the
# search normally (exit status 0).
#
# Timing notes (all verified in the 1-CPU trial container):
#   * the tree must be large enough that the walk is still resolving entries
#     when the cwd is removed: the default print mode needs ~400k files
#     (resolution phase ~1s >> 0.2s deletion), while -x / -X exec modes pace
#     the resolution on the drain of the bounded channel, so ~80k files are
#     enough there (set CASE_FILES accordingly);
#   * the deleter waits for the fd process to appear (pgrep) before deleting,
#     so the removal always lands mid-search, never before it starts.
set -u

FD_BIN=${FD_BIN:-/app/src/target/debug/fd}
N=${CASE_FILES:-400000}
BIG=/tmp/fd-case-big
CWD=/tmp/fd-case-cwd
OUT_FILE=/tmp/fd-case-out.txt
ERR_FILE=/tmp/fd-case-err.txt
DELETER_PID=

# Create the big tree + the working directory with the symlink root, and
# cd into the working directory. Idempotent: an existing complete tree is
# reused (all three cases share one tree per verifier run).
setup_search_tree() {
  rm -rf "$CWD"
  mkdir -p "$BIG"
  cd "$BIG"
  if [ "$(ls -1A | wc -l)" -lt "$N" ]; then
    rm -rf "$BIG"; mkdir -p "$BIG"; cd "$BIG"
    for i in $(seq 1 "$N"); do : > "f$i"; done
  fi
  mkdir -p "$CWD"
  ln -sf "$BIG" "$CWD/link"
  cd "$CWD"
}

# Start the background deleter that removes the working directory mid-walk
# (~0.2 s after the fd process appears).
start_deleter() {
  (
    for _ in $(seq 1 12); do
      pgrep -x fd >/dev/null 2>&1 && break
      sleep 0.05
    done
    sleep 0.2
    rm -f "$CWD/link"
    rmdir "$CWD" 2>/dev/null
  ) &
  DELETER_PID=$!
}

stop_deleter() {
  wait "$DELETER_PID" 2>/dev/null || true
}

cleanup_case() {
  /bin/rm -rf "$CWD" "$OUT_FILE" "$ERR_FILE" 2>/dev/null
  cd /
}

cleanup_tree() {
  /bin/rm -rf "$BIG" 2>/dev/null
}

# Assert the fixed behaviour. A graceful outcome is either:
#   * exit status 1 with the filesystem error reported (--show-errors), or
#   * exit status 0 with matches produced when this mode prints them
#     (REQUIRE_OUT=1), or exit status 0 without output in exec modes that
#     never print matches (REQUIRE_OUT=0).
# A Rust panic (exit 101 / "panicked" / an unnamed-thread backtrace header)
# is always a failure. Arguments: RC OUT_TEXT ERR_TEXT REQUIRE_OUT
assert_graceful_ok() {
  rc=$1
  out=$2
  err=$3
  require_out=$4
  if printf '%s' "$err" | grep -q "panicked"; then
    echo "FAIL: output contains a Rust panic message" >&2
    printf '%s\n' "$err" | head -8 | sed 's/^/    /' >&2
    return 1
  fi
  if printf '%s' "$err" | grep -q "thread '<unnamed>'"; then
    echo "FAIL: output contains an unnamed-thread panic backtrace header" >&2
    printf '%s\n' "$err" | head -8 | sed 's/^/    /' >&2
    return 1
  fi
  case "$rc" in
    0)
      if [ "$require_out" = 1 ] && [ -z "$out" ]; then
        echo "FAIL: exit status 0 but no matches were produced (the search did not run)" >&2
        return 1
      fi
      echo "ok: search completed normally (exit 0, no panic)"
      return 0
      ;;
    1)
      if ! printf '%s' "$err" | grep -q "No such file or directory"; then
        echo "FAIL: exit status 1 but the filesystem error was not reported (--show-errors should print it)" >&2
        printf '%s\n' "$err" | head -6 | sed 's/^/    /' >&2
        return 1
      fi
      echo "ok: search aborted gracefully (exit 1, no panic) with the filesystem error reported"
      return 0
      ;;
    *)
      echo "FAIL: expected a graceful exit (0 or 1), got $rc (panicking run? see stderr)" >&2
      printf '%s\n' "$err" | head -8 | sed 's/^/    /' >&2
      return 1
      ;;
  esac
}

# The background deleter must have actually removed the working directory;
# otherwise the case never exercised the mid-walk removal and is vacuous.
assert_cwd_removed() {
  if [ -d "$CWD" ]; then
    echo "FAIL: the working directory was not removed (background deleter did not engage)" >&2
    return 1
  fi
  echo "ok: working directory was removed mid-walk"
  return 0
}