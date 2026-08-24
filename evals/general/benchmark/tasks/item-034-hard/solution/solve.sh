#!/bin/bash
# Oracle solution for item-034-hard.
# Authors the two graded server-side deliverables and starts the supervised
# desktop stack:
#   /app/server/bridge.py       (the websockify WebSocket<->RFB bridge)
#   /app/server/supervisor.py   (process supervisor with auto-restart + readiness)
mkdir -p /app/server /app/runtime

write_bridge() {
cat > /app/server/bridge.py <<'PYEOF'
#!/usr/bin/env python3
"""bridge.py — the websockify hop: WebSocket<->RFB (agent-authored).

Accepts WebSocket upgrades; per client opens a TCP connection to the RFB/VNC
target and relays bytes both ways. Client frames are masked, server frames
unmasked (RFC 6455). Partial frames and segments are reassembled.
"""
import argparse
import base64
import hashlib
import os
import socket
import struct
import threading
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def recv_exact(sock, n, timeout=10.0):
    data = b""
    end = time.time() + timeout
    while len(data) < n and time.time() < end:
        try:
            sock.settimeout(max(0.2, end - time.time()))
            chunk = sock.recv(n - len(data))
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    return data


def read_head(sock):
    data = b""
    while b"\r\n\r\n" not in data and len(data) < 8192:
        c = sock.recv(4096)
        if not c:
            break
        data += c
    return data


def recv_payload(ws):
    h = recv_exact(ws, 2)
    if not h or len(h) < 2:
        return None
    masked = bool(h[1] & 0x80)
    ln = h[1] & 0x7F
    if ln == 126:
        e = recv_exact(ws, 2)
        if len(e) < 2:
            return None
        ln = struct.unpack(">H", e)[0]
    elif ln == 127:
        e = recv_exact(ws, 8)
        if len(e) < 8:
            return None
        ln = struct.unpack(">Q", e)[0]
    k = recv_exact(ws, 4) if masked else None
    p = recv_exact(ws, ln)
    if k and len(p) == ln:
        p = bytes(b ^ k[i % 4] for i, b in enumerate(p))
    return p


def handle(conn, target_addr):
    try:
        head = read_head(conn)
        if b"websocket" not in head.lower():
            return
        key = None
        for line in head.split(b"\r\n"):
            if line.lower().startswith(b"sec-websocket-key:"):
                key = line.split(b":", 1)[1]
                break
        if not key:
            return
        accept = base64.b64encode(
            hashlib.sha1((key.decode().strip() + GUID).encode()).digest()).decode()
        conn.sendall(("HTTP/1.1 101 Switching Protocols\r\n"
                      "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
        tcp = socket.create_connection(target_addr, timeout=10.0)
        tcp.settimeout(0.2)

        def to_client():
            while True:
                try:
                    chunk = tcp.recv(4096)
                except socket.timeout:
                    continue
                except OSError:
                    break
                if not chunk:
                    break
                ln = len(chunk)
                head2 = bytearray([0x02, ln]) if ln < 126 else bytearray([0x02, 126]) + struct.pack(">H", ln)
                try:
                    conn.sendall(bytes(head2) + chunk)
                except OSError:
                    break

        th = threading.Thread(target=to_client, daemon=True)
        th.start()
        while True:
            data = recv_payload(conn)
            if data is None:
                break
            try:
                tcp.sendall(data)
            except OSError:
                break
        tcp.close()
        th.join(timeout=1)
    except OSError:
        pass
    except Exception:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    port = int(os.environ.get("BRIDGE_PORT", "8080"))
    target = os.environ.get("BRIDGE_TARGET", "127.0.0.1:5901")
    th, tp = target.split(":")
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(64)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn, (th, int(tp))), daemon=True).start()


if __name__ == "__main__":
    main()
PYEOF
}

write_supervisor() {
cat > /app/server/supervisor.py <<'PYEOF'
#!/usr/bin/env python3
"""supervisor.py — process supervisor for the VNC/websockify/nginx stack.

Runs three named workers ('vnc', 'bridge', 'web'), respawns any that die,
maintains /app/runtime/pids.json and /app/runtime/ready.json, and only
declares READY after real readiness (ports connectable + target answers an
RFB greeting).

Commands:
  python3 supervisor.py            start and supervise (default)
  python3 supervisor.py stop       stop all supervised workers and exit
  python3 supervisor.py status     print pids + readiness
"""
import json
import os
import socket
import subprocess
import sys
import time

VNC_PORT = 5901
BRIDGE_PORT = 8080
WEB_PORT = 8081
RT = "/app/runtime"
PIDS_FILE = os.path.join(RT, "pids.json")
READY_FILE = os.path.join(RT, "ready.json")
CONF = "/app/server/nginx.conf"
DEAD = subprocess.DEVNULL
workers_order = ["vnc", "bridge", "web"]


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def port_up(port, t=1.0):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=t)
        s.close()
        return True
    except Exception:
        return False


def rfb_ok():
    try:
        s = socket.create_connection(("127.0.0.1", VNC_PORT), timeout=2.0)
        s.settimeout(2.0)
        g = s.recv(12)
        s.close()
        return g.startswith(b"RFB ")
    except Exception:
        return False


def write_nginx_conf():
    conf = (
        "events {\n}\n"
        "http {\n"
        "  map $http_upgrade $connection_upgrade {\n"
        "      default upgrade;\n"
        "      '' close;\n"
        "  }\n"
        "  server {\n"
        "      listen 127.0.0.1:%d;\n"
        "      server_name _;\n"
        "      root /app/web;\n"
        "      index index.html;\n"
        "      location / { try_files $uri $uri/ /index.html; }\n"
        "      location /ws {\n"
        "          proxy_pass http://127.0.0.1:%d;\n"
        "          proxy_http_version 1.1;\n"
        "          proxy_set_header Upgrade $http_upgrade;\n"
        "          proxy_set_header Connection $connection_upgrade;\n"
        "      }\n"
        "  }\n}\n"
    ) % (WEB_PORT, BRIDGE_PORT)
    with open(CONF, "w") as f:
        f.write(conf)


def spawn(name, procs):
    if name == "vnc":
        env = dict(os.environ)
        env["VNC_HOST"] = "127.0.0.1"
        env["VNC_PORT"] = str(VNC_PORT)
        env["KEYS_LOG"] = "/app/keys.log"
        p = subprocess.Popen([sys.executable, "/app/desktop/vnc_target.py"],
                             env=env, cwd="/app",
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif name == "bridge":
        env = dict(os.environ)
        env["BRIDGE_PORT"] = str(BRIDGE_PORT)
        env["BRIDGE_TARGET"] = "127.0.0.1:%d" % VNC_PORT
        p = subprocess.Popen([sys.executable, "/app/server/bridge.py"], env=env,
                             cwd="/app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:  # web
        write_nginx_conf()
        subprocess.run(["nginx", "-s", "stop"], capture_output=True)
        os.makedirs("/tmp/t34hng", exist_ok=True)
        try:
            p = subprocess.Popen(["nginx", "-c", CONF, "-p", "/tmp/t34hng"],
                                 cwd="/app", stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
        except Exception:
            p = None
    if p is not None:
        procs[name] = p
        time.sleep(0.3)


def stop(pids):
    for name, pid in pids.items():
        try:
            import signal
            os.kill(int(pid), signal.SIGKILL)
        except Exception:
            pass
    subprocess.run(["nginx", "-s", "stop"], capture_output=True)
    for f in (PIDS_FILE, READY_FILE):
        try:
            os.remove(f)
        except OSError:
            pass
    return 0


def supervise():
    procs = {}
    pids = {}
    spawn("vnc", procs); spawn("bridge", procs); spawn("web", procs)
    for n, p in procs.items():
        pids[n] = p.pid
    write_json(PIDS_FILE, pids)
    last_states = {}
    while True:
        # respawn dead workers
        changed = False
        for name in list(procs.keys()):
            p = procs[name]
            if p.poll() is not None:
                del procs[name]
                spawn(name, procs)
                changed = True
        if changed:
            pids = {n: p.pid for n, p in procs.items()}
            write_json(PIDS_FILE, pids)
        # readiness = all ports up + target answers an RFB handshake
        healthy = (port_up(VNC_PORT) and port_up(BRIDGE_PORT)
                   and port_up(WEB_PORT) and rfb_ok() and len(procs) >= 3)
        if healthy and not os.path.exists(READY_FILE):
            write_json(READY_FILE,
                       {"ready": True,
                        "ports": {"vnc": VNC_PORT, "bridge": BRIDGE_PORT, "web": WEB_PORT},
                        "rfb_ok": True,
                        "ts": time.time()})
        time.sleep(0.4)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "start"
    if cmd == "stop":
        try:
            pids = json.load(open(PIDS_FILE))
        except Exception:
            pids = {}
        return stop(pids)
    if cmd == "status":
        try:
            print(open(READY_FILE).read())
        except Exception:
            print("not ready")
        return 0
    supervise()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF
}

write_bridge
write_supervisor

# Idempotent bring-up: stop anything stale, start supervised stack, wait ready.
python3 /app/server/supervisor.py stop 2>/dev/null || true
python3 /app/server/supervisor.py start &
SUP_PID=$!
# wait for real readiness (RFB handshake present)
for i in $(seq 1 120); do
  if [ -f /app/runtime/ready.json ] && python3 -c "import json;print(json.load(open('/app/runtime/ready.json')).get('ready'))" 2>/dev/null | grep -q True; then
    break
  fi
  sleep 1
done
python3 /app/server/supervisor.py status
# Tear the stack down cleanly so the verifier (which drives its own fresh
# supervisor from a pristine state) does not race a leftover supervisor.
python3 /app/server/supervisor.py stop 2>/dev/null || true
kill "$SUP_PID" 2>/dev/null || true
wait "$SUP_PID" 2>/dev/null || true
nginx -s stop 2>/dev/null || true
rm -f /app/runtime/ready.json /app/runtime/pids.json
exit 0