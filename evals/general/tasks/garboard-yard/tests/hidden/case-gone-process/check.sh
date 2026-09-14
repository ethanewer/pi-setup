#!/bin/bash
# Hidden case "gone-process": regression guard (vanished-process semantics).
#   pre-fix tree  : passes by construction (this is the unfixed behaviour);
#   repaired tree : MUST PASS (a correct fix is narrow, so the drop-on-
#                   vanished behaviour is preserved; an over-broad fix that
#                   swallows every exception or stops removing cache entries
#                   fails here).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

if ! python3 "$DIR/case_gone_process.py" > /tmp/hc-gone-fixed.log 2>&1; then
  echo "FAIL: case-gone-process failed against the repaired tree"
  tail -8 /tmp/hc-gone-fixed.log | sed 's/^/    /' >&2
  exit 1
fi
echo "ok: case-gone-process passes on the repaired tree (vanished-process semantics preserved)"
exit 0