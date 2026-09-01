#!/bin/bash
# Verifier for item-034-hard.
# Re-drives the supervised desktop stack (stop then fresh start), requires a
# REAL RFB-greeting readiness latch, a pid manifest, an adversarial concurrent
# key storm, and automatic restart of a killed worker.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/server/supervisor.py ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

score=$(python3 - <<'EOF'
import json, os, signal, socket, subprocess, sys, threading, time
import urllib.request

RT = "/app/runtime"
PIDS_FILE = os.path.join(RT, "pids.json")
READY_FILE = os.path.join(RT, "ready.json")
KEYS = "/app/keys.log"
VNC_PORT = 5901

STATE = {"score": 0.0}

def port_up(p, t=1.0):
    try:
        s = socket.create_connection(("127.0.0.1", p), timeout=t); s.close(); return True
    except Exception:
        return False

def keys_have(k):
    try:
        d = open(KEYS).read()
    except Exception:
        return False
    return ("KeyEvent %d " % k) in d

def web_up():
    try:
        with urllib.request.urlopen("http://127.0.0.1:8081/index.html", timeout=4) as r:
            return "Windows" in r.read().decode("utf-8", "replace")
    except Exception:
        return False

def stop_supervisor():
    try:
        subprocess.run([sys.executable, "/app/server/supervisor.py", "stop"],
                       capture_output=True, timeout=45)
    except Exception:
        pass
    for f in (PIDS_FILE, READY_FILE):
        try: os.remove(f)
        except OSError: pass

def validate():
    try:
        open(KEYS, "w").close()
    except Exception:
        pass

    stop_supervisor()
    sup = subprocess.Popen([sys.executable, "/app/server/supervisor.py", "start"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    ready_ok = False; manifest_ok = False
    end = time.time() + 150
    while time.time() < end:
        try:
            rd = json.load(open(READY_FILE))
            pm = json.load(open(PIDS_FILE))
            ready_ok = bool(rd.get("ready")) and bool(rd.get("rfb_ok"))
            manifest_ok = all(n in pm for n in ("vnc", "bridge", "web"))
            if ready_ok and manifest_ok:
                break
        except Exception:
            pass
        time.sleep(1)

    try:
        pids = json.load(open(PIDS_FILE))
    except Exception:
        pids = {}

    sys.path.insert(0, "/app/lib")
    try:
        from rfb_ws import rfb_send_key
    except Exception:
        rfb_send_key = None

    landed = []
    def stress(k):
        try:
            if rfb_send_key is not None and rfb_send_key("127.0.0.1", 8081, k, path="/ws"):
                wt = time.time() + 30
                while time.time() < wt and not keys_have(k):
                    time.sleep(0.05)
        except Exception:
            pass
        if keys_have(k):
            landed.append(k)

    ths = [threading.Thread(target=stress, args=(k,)) for k in range(65, 89)]
    for t in ths: t.start()
    for t in ths: t.join()

    restart_ok = False
    try:
        old_pid = int(pids["vnc"])
    except Exception:
        old_pid = 0
    if old_pid:
        try: os.kill(old_pid, signal.SIGKILL)
        except OSError: pass
        new_pid = None
        end = time.time() + 90
        while time.time() < end:
            try:
                pm = json.load(open(PIDS_FILE))
                npv = int(pm["vnc"])
                if npv != old_pid and port_up(VNC_PORT):
                    new_pid = npv; break
            except Exception:
                pass
            time.sleep(1)
        if new_pid is not None and rfb_send_key is not None:
            for _ in range(40):
                try:
                    if rfb_send_key("127.0.0.1", 8081, 89, path="/ws") and keys_have(89):
                        break
                except Exception:
                    pass
                time.sleep(1)
            restart_ok = (new_pid != old_pid) and port_up(VNC_PORT) and keys_have(89)

    # Check the web front end while the stack is still up (nginx dies on stop).
    web_ok = web_up()

    stop_supervisor()
    try: sup.terminate()
    except Exception: pass

    v = 0.0
    if ready_ok: v += 0.4
    if manifest_ok: v += 0.1
    nland = len(set(landed))
    if nland >= 22: v += 0.25
    elif nland >= 12: v += 0.15
    if restart_ok: v += 0.25
    if web_ok: v += 0.1
    STATE["score"] = round(min(v, 1.0), 2)

try:
    validate()
except Exception:
    pass
print(f"{STATE['score']:.2f}", end="")
EOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"