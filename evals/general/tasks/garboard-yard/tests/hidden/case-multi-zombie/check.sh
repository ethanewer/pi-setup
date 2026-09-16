#!/bin/bash
# Hidden case "multi-zombie": discriminating.
#   pre-fix tree  : must FAIL (the buggy iterator drops every zombie-condition
#                   process and forgets it in the cache);
#   repaired tree : must PASS.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

if /opt/prefix-venv/bin/python "$DIR/case_multi_zombie.py" > /tmp/hc-multi-pre.log 2>&1; then
  echo "FAIL: case-multi-zombie passed on the pristine pre-fix tree (case does not discriminate)"
  tail -5 /tmp/hc-multi-pre.log | sed 's/^/    /' >&2
  exit 1
fi
echo "ok: case-multi-zombie fails on the pre-fix tree, as required"

if ! python3 "$DIR/case_multi_zombie.py" > /tmp/hc-multi-fixed.log 2>&1; then
  echo "FAIL: case-multi-zombie failed against the repaired tree"
  tail -8 /tmp/hc-multi-fixed.log | sed 's/^/    /' >&2
  exit 1
fi
echo "ok: case-multi-zombie passes on the repaired tree"
exit 0