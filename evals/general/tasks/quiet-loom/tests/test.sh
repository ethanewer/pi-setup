#!/bin/bash
# Verifier for quiet-loom (executes-deliverable).
# 1) Loads /app/jupyter_notebook_config.py with Jupyter's own config loader and
#    checks the required values (file-content check).
# 2) Launches `jupyter server` with the agent's config under the visible profile
#    and under each hidden profile (rotated into /app/deploy_profile.json),
#    requiring a wildcard-interface bind on the profile-derived port and a
#    tokenless HTTP 200 from /api/status. Writes reward to
#    /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

CFG=/app/jupyter_notebook_config.py
PROFILE=/app/deploy_profile.json
PRISTINE_VISIBLE_PROFILE_SHA="$(sha256sum /app/deploy_profile.json 2>/dev/null | awk '{print $1}')"

# ------------------------------------------------------------ static file check
static_fail=0
if [ ! -f "$CFG" ]; then
    echo "config file missing: $CFG" >&2
    static_fail=1
else
    if ! python3 - "$CFG" <<'PY'
import json, sys
from traitlets.config import PyFileConfigLoader

cfg = PyFileConfigLoader(sys.argv[1]).load_config()
assert isinstance(cfg, dict), type(cfg)

def sect(name):
    assert name in cfg, "missing config section %s" % name
    return cfg[name]

def want(sect_name, key, expected):
    s = sect(sect_name)
    got = s.get(key, "<<absent>>")
    assert got == expected, "%s.%s = %r, expected %r" % (sect_name, key, got, expected)

# profile in place during this static check is the shipped visible one (9318)
want("ServerApp", "ip", "0.0.0.0")
want("NotebookApp", "ip", "0.0.0.0")
want("ServerApp", "port", 9318)
want("NotebookApp", "port", 9318)
want("ServerApp", "token", "")
want("ServerApp", "password", "")
want("NotebookApp", "token", "")
want("NotebookApp", "password", "")
want("ServerApp", "open_browser", False)
want("NotebookApp", "open_browser", False)
want("ServerApp", "allow_root", True)
print("static config check ok")
PY
    then
        echo "static config check FAILED" >&2
        static_fail=1
    fi
fi

# ------------------------------------------------------------ live server checks
live_fail=0

nonloopback_ip="$(python3 -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("10.254.254.254", 1))
    print(s.getsockname()[0])
except OSError:
    print("127.0.0.1")
finally:
    s.close()')"

check_server() {
    # $1 = expected port
    local exp_port="$1"
    rm -rf /tmp/ql_rd; mkdir -p /tmp/ql_rd
    jupyter server --config=/app/jupyter_notebook_config.py --no-browser \
        --allow-root --ServerApp.root_dir=/tmp/ql_rd >/tmp/ql_srv.log 2>&1 &
    local pid=$!
    local bound=""
    for i in $(seq 1 75); do
        if python3 - "$exp_port" <<'PY'
import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1)
    s.close(); raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
        then
            bound="$exp_port"; break
        fi
        sleep 0.4
    done
    local code=""
    local wide="no"
    if [ -n "$bound" ]; then
        code=$(python3 - "$exp_port" <<'PY'
import sys, urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:%s/api/status" % sys.argv[1], timeout=5) as r:
        print(r.status)
except Exception as exc:
    print("ERR:%s" % exc)
PY
)
        # wildcard bind means the server is reachable on a non-loopback address
        if python3 - "$nonloopback_ip" "$exp_port" <<'PY'
import socket, sys
try:
    s = socket.create_connection((sys.argv[1], int(sys.argv[2])), 2)
    s.close(); raise SystemExit(0)
except OSError:
    raise SystemExit(1)
PY
        then
            wide="yes"
        fi
    fi
    kill "$pid" 2>/dev/null || true
    pkill -f "jupyter-server" 2>/dev/null || true
    pkill -f "/usr/local/bin/jupyter" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 0.3
    if [ "$bound" != "$exp_port" ] || [ "$code" != "200" ] || [ "$wide" != "yes" ]; then
        echo "  live-case FAIL exp_port=$exp_port bound=$bound code=$code wide=$wide" >&2
        return 1
    fi
    echo "  live-case ok port=$exp_port code=$code wide=$wide" >&2
    return 0
}

# visible profile first (the shipped one must still be in place and intact)
visible_fail=0
if [ -z "$PRISTINE_VISIBLE_PROFILE_SHA" ]; then
    echo "visible profile /app/deploy_profile.json missing" >&2
    visible_fail=1
else
    if ! check_server 9318; then visible_fail=1; fi
fi
pkill -f "jupyter-server" 2>/dev/null || true
sleep 0.3

# hidden profiles
if [ -d /tests/hidden ]; then
    for case_dir in /tests/hidden/*/; do
        [ -f "$case_dir/profile.json" ] || continue
        [ -f "$case_dir/expected_port.txt" ] || continue
        exp="$(cat "$case_dir/expected_port.txt")"
        case "$exp" in
            ''|*[!0-9]*) echo "bad expected_port in $case_dir" >&2; live_fail=1; continue;;
        esac
        cp "$case_dir/profile.json" "$PROFILE"
        if ! check_server "$exp"; then live_fail=1; fi
        pkill -f "jupyter-server" 2>/dev/null || true
        sleep 0.3
    done
else
    echo "no /tests/hidden" >&2
    live_fail=1
fi

# ---------------------------------------------------------------- reward
if [ "$static_fail" -eq 0 ] && [ "$visible_fail" -eq 0 ] && [ "$live_fail" -eq 0 ]; then
    reward=1
else
    reward=0
    echo "static_fail=$static_fail visible_fail=$visible_fail live_fail=$live_fail" >&2
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
