#!/usr/bin/env bash
# Verifier for gale-keystone. Runs as root after the agent finishes; /tests is
# read-only. Ends by writing the reward to /logs/verifier/reward.txt.
set -u

REWARD=0
echo "$REWARD" > /logs/verifier/reward.txt
PORT=8129
BASE="http://127.0.0.1:$PORT"
fail=0

err() { echo "FAIL: $*"; fail=1; }
ok()  { echo "ok: $*"; }

# ---- every deliverable must exist ----
for f in /app/service.py /app/mgmt-request.sh /app/reserve.py /app/reservations.json \
         /app/solve.py /app/answer.txt /app/value.py /app/value-test.log; do
  [ -e "$f" ] || err "missing deliverable $f"
done
[ "$fail" != 0 ] && { echo "reward=$REWARD"; exit 0; }

# ---- start the service ----
python3 /app/service.py >/tmp/service.log 2>&1 &
SERV=$!
trap 'kill $SERV 2>/dev/null || true' EXIT
up=0
for _ in $(seq 1 75); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/no-such-path" 2>/dev/null || true)
  if [ "$code" = "404" ]; then up=1; break; fi
  sleep 0.2
done
[ "$up" = 1 ] || err "service did not come up on port $PORT"

# ---- C-5c246195 / C-94d4d415: malformed bodies -> 400 + message ----
bad_body() {
  local desc=$1; shift
  local code
  code=$(curl -s -o /tmp/resp.txt -w '%{http_code}' "$BASE/reserve" "$@")
  if [ "$code" != "400" ]; then err "malformed($desc): status $code != 400"; return; fi
  grep -q '"message"' /tmp/resp.txt || err "malformed($desc): body lacks message field"
}
[ "$fail" = 0 ] && bad_body "missing-venue" -H "Content-Type: application/json" -d '{"company":"Zeph Co"}'
[ "$fail" = 0 ] && bad_body "missing-company" -H "Content-Type: application/json" -d '{"venue":"West Field"}'
[ "$fail" = 0 ] && ok "C-5c246195 visible malformed bodies -> 400 + message"

# ---- C-9c4bf0c8: crafted management request must be answered ----
if [ "$fail" = 0 ]; then
  if bash /app/mgmt-request.sh >/tmp/mgmt.out 2>&1; then
    grep -q '^200$' /tmp/mgmt.out || err "mgmt-request.sh did not print HTTP 200"
    grep -q 'token.entry.glacier.a1b2c3' /tmp/mgmt.out || err "mgmt-request.sh reply lacks credentials"
    ok "C-9c4bf0c8 crafted management request answered with credentials"
  else
    err "mgmt-request.sh exited nonzero"
  fi
fi

# ---- visible reservation recorded with company name ----
if [ "$fail" = 0 ]; then
  grep -q '"venue": "Woodbank Pavilion"' /app/reservations.json \
    || err "visible reservation venue missing from reservations.json"
  grep -q '"company": "Keystone Freight"' /app/reservations.json \
    || err "visible reservation company missing from reservations.json"
  grep -q '"confirmation": "HARBOR-1"' /app/reservations.json \
    || err "visible reservation confirmation missing"
  ok "C-94d4d415 visible reservation recorded with company"
fi

# ---- hidden cases ----
if [ "$fail" = 0 ]; then
  for h in /tests/hidden/*.sh; do
    [ -f "$h" ] || continue
    echo "== hidden: $(basename "$h")"
    bash "$h" || err "hidden case $(basename "$h") failed"
  done
fi

# ---- C-2e1e47c4 / C-271f36bb: solve.py recomputes, answer.txt is exact ----
if [ "$fail" = 0 ]; then
  if ! python3 /app/solve.py >/tmp/solve.out 2>&1; then
    err "solve.py exited nonzero"
  else
    [ "$(wc -l < /app/answer.txt)" = "1" ] || err "answer.txt must contain exactly one line"
    grep -qx '8137' /app/answer.txt || err "answer.txt is not exactly '8137' (got: $(cat /app/answer.txt))"
    grep -q '^8137$' /tmp/solve.out || err "solve.py stdout should be the integer too"
    if [ "$fail" = 0 ]; then ok "C-2e1e47c4/C-271f36bb solve.py runs and answer.txt holds the integer"; fi
  fi
fi

# ---- C-85e1b197: value object hash/equality/cache invariants ----
if [ "$fail" = 0 ]; then
  if python3 - <<'PY'
import sys
sys.path.insert(0, "/app")
from value import AssetKey

a = AssetKey("dup:owl-1")
b = AssetKey("dup:owl-1")       # must hit the instance cache
c = AssetKey("fox-9")           # distinct value
d = AssetKey("other:x2")

assert a == b, "equality broken"
assert a is b, "instance cache no longer dedups by equality"
assert hash(a) == hash(b), "hash not consistent with equality"
assert hash(a) == hash("dup:owl-1"), "hash is not value-derived"
assert a != c and a is not c and c is not d, "distinct values collapsed"
assert hash(c) != hash(d), "distinct values share a hash"
s = set(); s.add(a); assert len(s) == 1, "set size wrong"
m = {a: 1}; assert m[b] == 1, "dict lookup via equal key broken"
print("VALUE-INVARIANTS-OK")
PY
  then
    grep -q 'VALUE-SELFCHECK-OK' /app/value-test.log \
      || err "value-test.log lacks selfcheck marker"
    ok "C-85e1b197 hash value-derived while equality+cache intact"
  else
    err "value object invariants failed"
  fi
fi

# ---- reward ----
if [ "$fail" = 0 ]; then
  REWARD=1
fi
echo "$REWARD" > /logs/verifier/reward.txt
echo "rewrite reward=$REWARD"
exit 0