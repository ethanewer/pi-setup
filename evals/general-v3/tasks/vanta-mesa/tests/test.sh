#!/usr/bin/env bash
# Verifier for vanta-mesa: enforces the no-modify rule on the supplied origin
# fixtures, then EXECUTES the deliverable client (/app/solve.py) against the
# visible reference origin and every hidden origin scenario in /tests/hidden,
# comparing reports via /tests/verify.py. Also checks the visible-case
# deliverable /app/answer.json. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
cd /app || exit 1
mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied origin fixtures (the instruction tells the
# agent not to modify them; tampering defeats the visible-case check).
PRISTINE_ORIGIN_SHA="e1d09b730ac939dad50dcd2f0bc85d61a39d59f51c8131c8498b01089dabcce6"
PRISTINE_CONFIG_SHA="2d2d7aee398607a8672f8cc14faf95d9c7c56d47880ba9206baeb73ccac14c7b"

guard=0
for pair in "/app/origin.py:$PRISTINE_ORIGIN_SHA" "/app/ref_config.json:$PRISTINE_CONFIG_SHA"; do
    f="${pair%%:*}"; want="${pair#*:}"
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        guard=1
    else
        actual="$(sha256sum "$f" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $f was modified" >&2
            guard=1
        fi
    fi
done

if [ ! -f /app/solve.py ]; then
    echo "FAIL missing /app/solve.py"
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

# run_scenario <config> <port> <outfile>: start origin, wait ready, run client
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
    sys.exit(1)' 2>/dev/null; then
            ready=1; break
        fi
        sleep 0.2
    done
    if [ "$ready" != "1" ]; then
        kill $pid 2>/dev/null; wait $pid 2>/dev/null
        return 1
    fi
    python3 /app/solve.py --origin "http://127.0.0.1:$port" --out "$out"
    local rc=$?
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return $rc
}

VIS_OK=0
if run_scenario /app/ref_config.json 20090 /tmp/vm_vis.json \
   && python3 /tests/verify.py /app/ref_config.json /tmp/vm_vis.json; then
    VIS_OK=1
fi

# h1: clean whitespace, integral price, sold-out record.
H1_OK=0
if run_scenario /tests/hidden/h1.json 20091 /tmp/vm_h1.json \
   && python3 /tests/verify.py /tests/hidden/h1.json /tmp/vm_h1.json; then
    H1_OK=1
fi

# h2: decoy articles with identical classes, entity-encoded cultivars,
# missing price/stock spans, fractional/sub-unit prices, messy whitespace.
H2_OK=0
if run_scenario /tests/hidden/h2.json 20092 /tmp/vm_h2.json \
   && python3 /tests/verify.py /tests/hidden/h2.json /tmp/vm_h2.json; then
    H2_OK=1
fi

# h3: empty offers section -> plants must be [].
H3_OK=0
if run_scenario /tests/hidden/h3.json 20093 /tmp/vm_h3.json \
   && python3 /tests/verify.py /tests/hidden/h3.json /tmp/vm_h3.json; then
    H3_OK=1
fi

# /app/answer.json must be the saved visible-case report.
ANS_OK=0
if [ -f /app/answer.json ] \
   && python3 /tests/verify.py /app/ref_config.json /app/answer.json; then
    ANS_OK=1
fi

echo "guard=$guard visible=$VIS_OK h1=$H1_OK h2=$H2_OK h3=$H3_OK answer=$ANS_OK"

if [ "$guard" = "0" ] && [ "$VIS_OK" = "1" ] && [ "$H1_OK" = "1" ] \
   && [ "$H2_OK" = "1" ] && [ "$H3_OK" = "1" ] && [ "$ANS_OK" = "1" ]; then
    reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0
