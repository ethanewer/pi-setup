#!/bin/bash
# Verifier for item-040-main: checks the running mail platform state and workflows.
mkdir -p /logs/verifier

points=0

# ---- 1. processes alive ----
proc_ok=0
if pgrep -f "mailplatform/mailservice.py" >/dev/null 2>&1; then proc_ok=$((proc_ok+1)); fi
if pgrep -f "mailplatform/listmgr.py" >/dev/null 2>&1; then proc_ok=$((proc_ok+1)); fi
if [ "$proc_ok" = "2" ]; then points=$((points+20)); fi

# ---- 2. SMTP greeting ----
smtp_ok=$(python3 - <<'PY'
import socket
try:
    s=socket.create_connection(("127.0.0.1",2525),timeout=5)
    data=s.recv(256)
    s.close()
    print("OK" if data.startswith(b"220") else "FAIL")
except Exception:
    print("FAIL")
PY
)
if [ "$smtp_ok" = "OK" ]; then points=$((points+20)); fi

# ---- 3. list config ----
cfg_ok=$(python3 - <<'PY'
import json
ok=False
try:
    cfg=json.load(open("tmp/scratch/m40b/etc/maillists/announce.json"))
    ok = cfg.get("list")=="announce" and sorted(cfg.get("subscribers",[]))==["alice@example.test","bob@example.test"]
except Exception:
    ok=False
print("OK" if ok else "FAIL")
PY
)
if [ "$cfg_ok" = "OK" ]; then points=$((points+15)); fi

# ---- 4. delivery + confirmation workflows ----
workflow_ok=$(python3 - <<'PY'
import os, glob
def nmail(m):
    return len(glob.glob(os.path.join(m, "*.eml")))
ok=False
try:
    lmlog=open("tmp/scratch/m40b/srv/mail/logs/listmgr.log",encoding="utf-8").read()
    alice=nmail("tmp/scratch/m40b/srv/mail/alice")
    bob=nmail("tmp/scratch/m40b/srv/mail/bob")
    carol=nmail("tmp/scratch/m40b/srv/mail/carol")
    confirmed = os.path.exists("tmp/scratch/m40b/srv/mail/confirmed.txt") and "carol@example.test" in open("tmp/scratch/m40b/srv/mail/confirmed.txt").read()
    sub_ok = "subscribed carol@example.test" in lmlog
    deliver_alice = "alice@example.test ok" in lmlog
    deliver_bob = "bob@example.test ok" in lmlog
    deliver_carol = "carol@example.test ok" in lmlog
    ok = alice>=2 and bob>=2 and carol>=2 and confirmed and sub_ok and deliver_alice and deliver_bob and deliver_carol
except Exception:
    ok=False
print("OK" if ok else "FAIL")
PY
)
if [ "$workflow_ok" = "OK" ]; then points=$((points+45)); fi

echo "$points" > tmp/scratch/reward40.txt