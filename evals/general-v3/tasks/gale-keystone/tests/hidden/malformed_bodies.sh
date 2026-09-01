#!/usr/bin/env bash
# Hidden case 1: edge/malformed POST bodies to /reserve must all yield
# HTTP 400 with a "message" field in the body.
set -u
BASE="http://127.0.0.1:8129"
fails=0

check() {
  local desc=$1; shift
  local code body
  body=$(mktemp)
  code=$(curl -s -o "$body" -w '%{http_code}' "$BASE/reserve" "$@")
  if [ "$code" != "400" ]; then
    echo "hidden-malformed($desc): status $code != 400"
    fails=1
  fi
  grep -q '"message"' "$body" || { echo "hidden-malformed($desc): no message field"; fails=1; }
  rm -f "$body"
}

# both required fields absent
check "missing-both" -H "Content-Type: application/json" -d '{}'
# required field present but wrong type (non-text)
check "numeric-company" -H "Content-Type: application/json" -d '{"venue":"Ursa Yard","company":42}'
# valid JSON but an array, not an object
check "json-array" -H "Content-Type: application/json" -d '[{"venue":"V"}]'
# valid JSON sent with a non-JSON content type
check "wrong-content-type" -H "Content-Type: text/plain" -d '{"venue":"V","company":"C"}'
# body is a scalar
check "json-scalar" -H "Content-Type: application/json" -d '"just-a-string"'

[ "$fails" = 0 ] && echo "hidden-malformed: all edge bodies refused with 400+message"
exit "$fails"