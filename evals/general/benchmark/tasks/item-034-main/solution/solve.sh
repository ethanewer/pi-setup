#!/bin/bash
# Oracle solution for item-034-main.
# Writes the graded deliverable /app/up.py and runs it so the stack is up and
# the end-to-end keyboard path is proven.

write_up_py() {
cat > /app/up.py <<'PYEOF'
#!/usr/bin/env python3
"""up.py — orchestrate the Windows-3.11 remote-desktop VNC stack (item-034)."""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

VNC = ("127.0.0.1", 5901)
BRIDGE = ("127.0.0.1", 8080)
WEB = ("127.0.0.1", 8081)
WS_PATH = "/ws"
KEYS_LOG = "/app/keys.log"
NGINX_CONF = "/app/nginx.conf"

sys.path.insert(0, "/app/lib")
try:
    from rfb_ws import rfb_send_key as _send_key
except Exception:
    _send_key = None


def wait_port(addr, timeout=45.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            s = socket.create_connection(addr, timeout=1.0)
            s.close()
            return True
        except OSError:
            time.sleep(0.25)
    return False


def web_up_now():
    if not wait_port(WEB, 2.0):
        return False
    try:
        with urllib.request.urlopen("http://127.0.0.1:8081/index.html", timeout=3) as r:
            return "Windows" in r.read().decode("utf-8", "replace")
    except Exception:
        return False


def ensure_vnc():
    if not wait_port(VNC, 2.0):
        env = dict(os.environ)
        env["VNC_HOST"] = "127.0.0.1"
        env["VNC_PORT"] = "5901"
        subprocess.Popen(
            [sys.executable, "/app/desktop/vnc_target.py"],
            env=env, cwd="/app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    return wait_port(VNC, 45.0)


def ensure_bridge():
    if not wait_port(BRIDGE, 2.0):
        subprocess.Popen(
            [sys.executable, "/app/lib/ws_bridge.py", "--host", "127.0.0.1",
             "--port", "8080", "--target", "127.0.0.1:5901"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    return wait_port(BRIDGE, 45.0)


def ensure_nginx():
    if web_up_now():
        return True
    conf = (
        "events {\n}\n"
        "http {\n"
        "  map $http_upgrade $connection_upgrade {\n"
        "      default upgrade;\n"
        "      '' close;\n"
        "  }\n"
        "  server {\n"
        "      listen 127.0.0.1:8081;\n"
        "      server_name _;\n"
        "      root /app/web;\n"
        "      index index.html;\n"
        "      location / { try_files $uri $uri/ /index.html; }\n"
        "      location /ws {\n"
        "          proxy_pass http://127.0.0.1:8080;\n"
        "          proxy_http_version 1.1;\n"
        "          proxy_set_header Upgrade $http_upgrade;\n"
        "          proxy_set_header Connection $connection_upgrade;\n"
        "          proxy_read_timeout 3600s;\n"
        "          proxy_send_timeout 3600s;\n"
        "      }\n"
        "  }\n}\n"
    )
    with open(NGINX_CONF, "w") as f:
        f.write(conf)
    subprocess.run(["nginx", "-s", "stop"], capture_output=True)
    os.makedirs("/tmp/t32ngx", exist_ok=True)
    subprocess.Popen(
        ["nginx", "-c", NGINX_CONF, "-p", "/tmp/t32ngx"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    end = time.time() + 20
    while time.time() < end:
        if web_up_now():
            return True
        time.sleep(0.25)
    return False


def keys_log_has(keysym):
    try:
        with open(KEYS_LOG) as f:
            data = f.read()
    except FileNotFoundError:
        return False
    return ("KeyEvent %d " % keysym) in data


def wait_for_key(keysym, timeout=30.0):
    end = time.time() + timeout
    while time.time() < end:
        if keys_log_has(keysym):
            return True
        time.sleep(0.25)
    return False


def main():
    ready = {
        "vnc": ensure_vnc(),
        "bridge": ensure_bridge(),
        "nginx": ensure_nginx(),
    }
    all_ready = all(ready.values())
    expected = [97, 65293]
    seen = []
    if all_ready and _send_key is not None:
        for k in expected:
            try:
                if _send_key("127.0.0.1", WEB[1], k, path="/ws"):
                    if wait_for_key(k):
                        seen.append(k)
            except Exception:
                pass
    keys_ok = expected == seen
    ok = all_ready and keys_ok
    report = {
        "ok": ok,
        "ready": ready,
        "ports": {"vnc": 5901, "bridge": 8080, "nginxFrontend": 8081, "wsPath": "/ws"},
        "keys_expected": expected,
        "keys_seen": seen,
        "web_page": "Windows for Workgroups 3.11",
    }
    with open("/app/report.json", "w") as f:
        json.dump(report, f, indent=2)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
PYEOF
}

write_up_py
python3 /app/up.py
rc=$?
echo "up.py rc=$rc"
cat /app/report.json 2>/dev/null
exit $rc