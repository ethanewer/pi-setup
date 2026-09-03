#!/bin/bash
# Interactive dialer for a colleague's phone microservice.
# Usage: dial_lib.sh <name> <port>
#
# Speaks the call protocol over HTTP for you: reads each line you type,
# POSTs it to the phone service, and prints whatever the person answers.
# The call ends when the other side hangs up (or you lose the stack).
set -u

NAME="${1:?usage: dial_lib.sh <name> <port>}"
PORT="${2:?usage: dial_lib.sh <name> <port>}"
BASE="http://127.0.0.1:${PORT}"
SESSION=""

post() {
  # post <line>; sets STATUS and fills REPLY_LINES
  local line="$1" payload resp
  payload=$(python3 -c 'import json,sys
print(json.dumps({"session": sys.argv[1], "line": sys.argv[2]}))' \
              "$SESSION" "$line") || { STATUS=error; REPLY_LINES=("dialer: could not encode line."); return; }
  if ! resp=$(curl -s -m 15 -X POST "${BASE}/call" \
                -H 'Content-Type: application/json' -d "$payload"); then
    STATUS=error
    REPLY_LINES=("dialer: no answer from ${NAME} (stack down? try /opt/offsite/up.sh)")
    return
  fi
  # a fresh CALL assigns the session server-side
  if [ -z "$SESSION" ]; then
    SESSION=$(printf '%s' "$resp" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("session",""))' 2>/dev/null || echo "")
  fi
  STATUS=$(printf '%s' "$resp" | python3 -c 'import json,sys
print(json.load(sys.stdin).get("status","error"))' 2>/dev/null || echo error)
  mapfile -t REPLY_LINES < <(printf '%s' "$resp" | python3 -c 'import json,sys
for l in json.load(sys.stdin).get("reply", []):
    print(l)' 2>/dev/null)
}

echo "* dialing ${NAME} on 127.0.0.1:${PORT} ..."
post "CALL"
for l in "${REPLY_LINES[@]}"; do echo "${NAME}: ${l}"; done
if [ "$STATUS" != "talking" ]; then
  echo "* click."
  exit 0
fi

while true; do
  if ! read -r -p "> " input; then
    echo
    break
  fi
  [ -z "${input//[[:space:]]/}" ] && continue
  post "$input"
  for l in "${REPLY_LINES[@]}"; do echo "${NAME}: ${l}"; done
  if [ "$STATUS" = "ended" ]; then
    echo "* click."
    break
  fi
  if [ "$STATUS" = "error" ]; then
    break
  fi
done
