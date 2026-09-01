#!/usr/bin/env bash
# willow-bridge verifier (executes-deliverable).
# Runs the agent's two /app deliverables on hidden inputs and rewards 1 only
# when every independent check passes. Never runs solve.sh (negative control
# must give REWARD=0).
set -u

LIST=/logs/verifier
mkdir -p "$LIST"  # reserved for future messages
reward=0

CFG=/app/jupyter_server_config.py
AWK=/app/ipv4_octet.awk
if [ ! -f "$CFG" ] || [ ! -f "$AWK" ]; then
    echo "0" > /logs/verifier/reward.txt
    echo "reward=0 (missing deliverables)" >&2
    exit 0
fi

# ---------------------------------------------------------------- Part A: awk corpus
# Independent ground truth computed in Python (split-based, NOT the regex the
# agent wrote) so the oracle is implementation-independent.
awk_fail=0
for f in /tests/hidden/ips_*.txt; do
    [ -f "$f" ] || continue
    gawk -f /app/ipv4_octet.awk "$f" > /tmp/wb_out_$$.txt 2>/dev/null
    if python3 - /tmp/wb_out_$$.txt "$f" <<'PY'
import sys
outfile, corpus = sys.argv[1], sys.argv[2]

def valid(t):
    # independent split-based oracle
    if len(t) == 0:
        return False
    parts = t.split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdigit():
            return False
        if len(p) > 1 and p[0] == "0":
            return False
        if not (0 <= int(p) <= 255):
            return False
    return True

exp = []
with open(corpus) as fh:
    for raw in fh:
        t = raw.strip("\r\n")
        t = t.strip(" \t")
        exp.append(("VALID\t" if valid(t) else "INVALID\t") + t)
got = []
with open(outfile) as fh:
    for raw in fh:
        got.append(raw.rstrip("\n"))

# Tolerate a trailing final empty line difference only if the last expected is blank
if got == exp:
    raise SystemExit(0)
for i, (g, e) in enumerate(zip(got, exp)):
    if g != e:
        sys.stderr.write("MISMATCH line %d got=%r exp=%r (file %s)\n" % (i, g, e, corpus))
        raise SystemExit(1)
if len(got) != len(exp):
    sys.stderr.write("LEN mismatch got=%d exp=%d (file %s)\n" % (len(got), len(exp), corpus))
    raise SystemExit(1)
raise SystemExit(0)
PY
    then
        :
    else
        awk_fail=1
    fi
    rm -f /tmp/wb_out_$$.txt
done

# ------------------------------------------------------- Part B: jupyter config
# Start `jupyter server` with the agent's config under each hidden port scenario.
# Expect a tokenless HTTP 200 from /api/status on the documented port.
cfg_fail=0

check_server() {
    # $1 = expected port; $2 = WILLOW_NOTE_PORT value or "unset"/"bad"
    local exp_port="$1"
    rm -rf /tmp/wb_rd; mkdir -p /tmp/wb_rd
    if [ -z "$2" ]; then
        env -u WILLOW_NOTE_PORT jupyter server \
            --config=/app/jupyter_server_config.py --no-browser --allow-root \
            --ServerApp.root_dir=/tmp/wb_rd >/tmp/wb_srv.log 2>&1 &
    else
        WILLOW_NOTE_PORT="$2" jupyter server \
            --config=/app/jupyter_server_config.py --no-browser --allow-root \
            --ServerApp.root_dir=/tmp/wb_rd >/tmp/wb_srv.log 2>&1 &
    fi
    local pid=$!
    local got=""
    for i in $(seq 1 60); do
        if python3 - "$exp_port" <<'PY'
import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1)
    s.close(); raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
        then
            got=$exp_port; break
        fi
        sleep 0.4
    done
    # Confirm it is loopback binding and tokenless via /api/status
    local code=""
    if [ -n "$got" ]; then
        code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${exp_port}/api/status" 2>/dev/null || echo ERR)
    fi
    kill "$pid" 2>/dev/null || true
    pkill -f "jupyter-server" 2>/dev/null || true
    pkill -f "/usr/local/bin/jupyter" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 0.3
    if [ "$got" != "$exp_port" ] || [ "$code" != "200" ]; then
        echo "  config-case FAIL exp_port=$exp_port env=|$2| bound=$got code=$code" >&2
        return 1
    fi
    echo "  config-case ok port=$exp_port code=$code" >&2
    return 0
}

for case in "8791:8791" "8442:8442" "8666:unset" "8666:oops-nonint"; do
    exp="${case%%:*}"; val="${case##*:}"
    if [ "$val" = unset ]; then
        if ! check_server "$exp" ""; then cfg_fail=1; fi
    elif [ "$val" = oops-nonint ]; then
        if ! check_server "$exp" "midnight-13"; then cfg_fail=1; fi
    else
        if ! check_server "$exp" "$val"; then cfg_fail=1; fi
    fi
    pkill -f "jupyter-server" 2>/dev/null || true
    sleep 0.3
done

# ---------------------------------------------------------------- reward
if [ "$awk_fail" -eq 0 ] && [ "$cfg_fail" -eq 0 ]; then
    reward=1
else
    reward=0
    echo "awk_fail=$awk_fail cfg_fail=$cfg_fail" >&2
fi

echo "${reward}" > /logs/verifier/reward.txt
echo "reward=${reward}" >&2
exit 0