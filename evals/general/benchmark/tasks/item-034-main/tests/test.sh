#!/bin/bash
# Verifier for item-034-main.
# Runs the agent's orchestrator /app/up.py (the only graded deliverable),
# then independently confirms the three-tier VNC/websockify/nginx stack is up
# and that keyboard events genuinely flow end-to-end through nginx /ws.
set -u
mkdir -p /logs/verifier

# 1) clean slate for key recording
if [ -f /app/keys.log ]; then
  truncate -s 0 /app/keys.log
fi

# 2) run the orchestrator (idempotent; brings tiers up if needed, probes keys)
if [ ! -f /app/up.py ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

timeout 200 python3 /app/up.py >/dev/null 2>&1 || :

score=$(python3 - <<'EOF'
import json, socket, sys, time
SCORE = {"v": 0.0}

def valuate():
    report = {}
    try:
        report = json.load(open("/app/report.json"))
    except Exception:
        pass

    def port_up(addr, t=1.0):
        try:
            s = socket.create_connection(addr, timeout=t); s.close(); return True
        except Exception:
            return False

    def web_up():
        try:
            import urllib.request
            with urllib.request.urlopen("http://127.0.0.1:8081/index.html", timeout=4) as r:
                return "Windows" in r.read().decode("utf-8", "replace")
        except Exception:
            return False

    def keys_have(k):
        try:
            d = open("/app/keys.log").read()
        except Exception:
            return False
        return ("KeyEvent %d " % k) in d

    ports_up = port_up(("127.0.0.1", 5901)) and port_up(("127.0.0.1", 8080)) and web_up()
    report_ok = bool(report.get("ok")) and \
                report.get("keys_seen") == report.get("keys_expected") and \
                report.get("ready", {}).get("nginx") and \
                report.get("ready", {}).get("bridge")

    got_ind = []
    try:
        sys.path.insert(0, "/app/lib")
        from rfb_ws import rfb_send_key
        for k in (98, 65361):
            try:
                if rfb_send_key("127.0.0.1", 8081, k, path="/ws"):
                    end = time.time() + 15
                    while time.time() < end and not keys_have(k):
                        time.sleep(0.25)
            except Exception:
                pass
            if keys_have(k):
                got_ind.append(k)
        ind_ok = got_ind == [98, 65361]
    except Exception:
        ind_ok = False

    v = 0.0
    if ports_up: v += 0.2
    if report_ok: v += 0.4
    if ind_ok: v += 0.2
    if web_up(): v += 0.2
    SCORE["v"] = round(v, 2)

try:
    validate()
except Exception:
    pass
print(f"{SCORE['v']:.2f}", end="")
EOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"