#!/bin/bash
# probe_cwd_removed.sh -- reproduce / verify the disappearing-working-directory
# crash in fd.
#
# Bug: when the directory a search was launched from is REMOVED while the
# search is still running, `fd --full-path` calls env::current_dir() for every
# matched entry; after the cwd has been unlinked that returns "not found", and
# the program panics and dies (exit 101) instead of finishing, skipping, or
# reporting the problem. Launching from a directory that was ALREADY gone at
# startup is handled gracefully; the mid-search removal is what aborts.
#
# This script reproduces the exact scenario:
#   * a large tree of plain files lives at /tmp/fd-probe-big;
#   * a fresh working directory /tmp/fd-probe-cwd containing a single symlink
#     `link` -> /tmp/fd-probe-big is created, and the script cd's into it;
#   * fd searches that symlink root (with --full-path, so every match needs
#     the current working directory to be resolved), while a background
#     process removes the working directory ~0.6 s after fd appears.
# The relative entry paths matter: an absolute search path would short-circuit
# the path resolution, so the symlink keeps the entries relative.
#
# Exit status of this probe:
#   0 : fixed  -- fd survived the cwd removal (clean exit, no panic);
#   1 : BUG PRESENT -- fd panicked (exit 101 or a panic message);
#   2 : fd binary is not built yet (build it first: cd /app/src && cargo build);
#   3 : unexpected (e.g. the search finished before the removal happened).
#
# The search tree is sized from FD_PROBE_N (default 160000 files); keep it
# large enough that the walk outlasts the deletion, or the race does not fire.
set -u

FD=${FD_BIN:-/app/src/target/debug/fd}
N=${FD_PROBE_N:-400000}

if [ ! -x "$FD" ]; then
  echo "the fd binary is not built yet; build it first with:"
  echo "  cd /app/src && cargo build"
  exit 2
fi

BIG=/tmp/fd-probe-big
CWD=/tmp/fd-probe-cwd

trap 'rm -rf "$BIG" "$CWD" 2>/dev/null; cd /' EXIT

# ---- build the search tree (idempotent: reuse an existing complete tree) ---
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

# ---- background deleter: wait until fd exists, then remove the cwd ---------
(
  for _ in $(seq 1 12); do
    pgrep -x fd >/dev/null 2>&1 && break
    sleep 0.05
  done
  sleep 0.2
  rm -f "$CWD/link"
  rmdir "$CWD" 2>/dev/null
) &
deleter=$!

set +e
"$FD" --full-path --show-errors -j 1 . link >/dev/null 2>"$BIG/err.txt"
rc=$?
set -e
wait "$deleter" 2>/dev/null || true

err=$(cat "$BIG/err.txt")
echo "[probe] fd exit code: $rc"
if [ "$rc" -eq 101 ] || printf '%s' "$err" | grep -q "panicked"; then
  echo "[probe] BUG PRESENT: fd panicked while its working directory was being removed mid-search:"
  printf '%s\n' "$err" | head -6 | sed 's/^/    /'
  exit 1
elif [ "$rc" -eq 1 ]; then
  echo "[probe] OK: fd survived the mid-search removal of its working directory (exit 1, no panic):"
  printf '%s\n' "$err" | head -3 | sed 's/^/    /'
  exit 0
else
  echo "[probe] unexpected exit code $rc (search may have finished before the removal); stderr was:"
  printf '%s\n' "$err" | head -10 | sed 's/^/    /'
  exit 3
fi