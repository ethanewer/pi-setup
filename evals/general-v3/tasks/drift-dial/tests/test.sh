#!/usr/bin/env bash
# test-dial verifier. Executes every deliverable and then writes the reward.
cd /app || exit 1
mkdir -p /logs/verifier
reward=0

# -------------------------------------------------------------
# 0) deliverable present
# -------------------------------------------------------------
if [ ! -x /app/solve.py ] && [ ! -f /app/solve.py ]; then
  echo "FAIL missing /app/solve.py"
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# -------------------------------------------------------------
# A) npm tree: the installed node_modules must be complete and resolve.
#    (start state ships a broken transitive pin; agent must repair + install)
# -------------------------------------------------------------
NPM_OK=0
if [ -d /app/node_modules/sector-srv ] || [ -L /app/node_modules/sector-srv ]; then
  : # top-level lib present as symlink or dir
fi
if node -e '
  const s = require("sector-srv");
  const st = s.stamp();
  if (st.stream !== "motif-core" || st.build !== 1) process.exit(1);
  console.log("sector-srv ok, motif linked");
' >/dev/null 2>&1; then
  NPM_OK=1
fi

# -------------------------------------------------------------
# B) run deliverable against a live origin scenario
#    args: <config> <port> <outfile>
# -------------------------------------------------------------
run_scenario() {
  local cfg="$1" port="$2" out="$3"
  python3 /app/origin.py "$cfg" "$port" &
  local pid=$!
  local ready=0
  for _ in $(seq 1 50); do
    if python3 -c 'import urllib.request,sys
try:
    urllib.request.urlopen("http://127.0.0.1:'$port'/", timeout=0.5).read()
    sys.exit(0)
except Exception:
    sys.exit(1)'; then
      ready=1; break
    fi
    sleep 0.2
  done
  if [ "$ready" != "1" ]; then
    kill $pid 2>/dev/null; wait $pid 2>/dev/null; return 1
  fi
  python3 /app/solve.py --origin "http://127.0.0.1:$port" --out "$out"
  local rc=$?
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  return $rc
}

# -------------------------------------------------------------
# C) execute the deliverable on the visible + hidden scenarios
# -------------------------------------------------------------
VIS_OK=0
if run_scenario /app/ref_config.json 20080 /tmp/vis.json \
   && python3 /tests/verify.py /app/ref_config.json /tmp/vis.json; then
  VIS_OK=1
fi

H1_OK=0
if run_scenario /tests/hidden/h1.json 20081 /tmp/h1.json \
   && python3 /tests/verify.py /tests/hidden/h1.json /tmp/h1.json; then
  H1_OK=1
fi

# h2: decoy table, footer/stats row, header row, short rows (missing cell),
# empty city cell, special-char station id, messy whitespace.
H2_OK=0
if run_scenario /tests/hidden/h2.json 20082 /tmp/h2.json \
   && python3 /tests/verify.py /tests/hidden/h2.json /tmp/h2.json; then
  H2_OK=1
fi

# h3: session edge -- server requires an X-Nonce header on POST /login
# and rotates the session cookie value after a successful login.
H3_OK=0
if run_scenario /tests/hidden/h3.json 20083 /tmp/h3.json \
   && python3 /tests/verify.py /tests/hidden/h3.json /tmp/h3.json; then
  H3_OK=1
fi

# -------------------------------------------------------------
# D) answer.json is a real saved, well-formed artifact
# -------------------------------------------------------------
ANS_OK=0
if [ -f /app/answer.json ]; then
  if python3 -c '
import json
d = json.load(open("/app/answer.json"))
assert isinstance(d.get("stations"), list) and len(d["stations"]) > 0
assert d.get("session", {}).get("logged_out") is True
print("answer ok")
' >/dev/null 2>&1; then
    ANS_OK=1
  fi
fi

echo "npm=$NPM_OK visible=$VIS_OK h1=$H1_OK h2=$H2_OK h3=$H3_OK answer=$ANS_OK"

if [ "$NPM_OK" = "1" ] && [ "$VIS_OK" = "1" ] && [ "$H1_OK" = "1" ] \
   && [ "$H2_OK" = "1" ] && [ "$H3_OK" = "1" ] && [ "$ANS_OK" = "1" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0