#!/bin/bash
# Hidden case "attrs-variant": discriminating.
#   pre-fix tree  : must FAIL (the instance is dropped, never yielded);
#   repaired tree : must PASS.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

if /opt/prefix-venv/bin/python "$DIR/case_attrs_variant.py" > /tmp/hc-attrs-pre.log 2>&1; then
  echo "FAIL: case-attrs-variant passed on the pristine pre-fix tree (case does not discriminate)"
  tail -5 /tmp/hc-attrs-pre.log | sed 's/^/    /' >&2
  exit 1
fi
echo "ok: case-attrs-variant fails on the pre-fix tree, as required"

if ! python3 "$DIR/case_attrs_variant.py" > /tmp/hc-attrs-fixed.log 2>&1; then
  echo "FAIL: case-attrs-variant failed against the repaired tree"
  tail -8 /tmp/hc-attrs-fixed.log | sed 's/^/    /' >&2
  exit 1
fi
echo "ok: case-attrs-variant passes on the repaired tree"
exit 0