#!/bin/bash
# Oracle: apply the modernisation repairs to the pristine clone in /app/src,
# build with the project's own stock flags, and leave the tree ready for the
# verifier (which rebuilds it from scratch under several flag sets).
set -u
cd /app/src/linuxdoom-1.10 || { echo "no /app/src/linuxdoom-1.10"; exit 1; }

python3 /solution/fix_doom.py || { echo "fix_doom.py failed"; exit 1; }

mkdir -p linux
if ! make > /tmp/oracle_build.log 2>&1; then
  echo "oracle: stock build failed:" >&2
  tail -20 /tmp/oracle_build.log >&2
  exit 1
fi

ls -la linux/linuxxdoom || { echo "oracle: no binary produced"; exit 1; }
echo "oracle: build ok"