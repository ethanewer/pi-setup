#!/bin/bash
# Verifier for item-040-hard: checks the recovered mail platform state:
# processes, SMTP greeting, provisioned Maildirs, confirmed membership,
# mailbox minima, and the log trail. Writes /logs/verifier/reward.txt (0..1).
set -uo pipefail

mkdir -p /logs/verifier
points=0

# ---- 1. both daemons alive ----
proc_ok=0
if pgrep -f "mailplatform/mailservice.py" >/dev/null 2>&1; then proc_ok=$((proc_ok+1)); fi
if pgrep -f "mailplatform/listmgr.py" >/dev/null 2>&1; then proc_ok=$((proc_ok+1)); fi
if [ "$proc_ok" = "2" ]; then points=$((points+15)); fi

# ---- 2. SMTP greeting ----
smtp_ok=$(python3 - <<'PY'
import socket
try:
    s = socket.create_connection(("127.0.0.1", 2525), timeout=5)
    ok = s.recv(256).startswith(b"220")
    s.close()
    print("OK" if ok else "FAIL")
except Exception:
    print("FAIL")
PY
)
if [ "$smtp_ok" = "OK" ]; then points=$((points+15)); fi

# ---- 3. the two deliberately-missing Maildirs are provisioned ----
dirs_ok=$(python3 - <<'PY'
import os
print("OK" if (os.path.isdir("/srv/mail/dave") and os.path.isdir("/srv/mail/carol")) else "FAIL")
PY
)
if [ "$dirs_ok" = "OK" ]; then points=$((points+10)); fi

# ---- 4. confirmed.txt records the new member ----
conf_ok=$(python3 - <<'PY'
ok = False
try:
    ok = "carol@example.test" in open("/srv/mail/confirmed.txt", encoding="utf-8").read()
except Exception:
    ok = False
print("OK" if ok else "FAIL")
PY
)
if [ "$conf_ok" = "OK" ]; then points=$((points+15)); fi

# ---- 5. mailbox minima: alice, bob, dave, carol each have >= 2 .eml ----
mbx_ok=$(python3 - <<'PY'
import glob, os
def cnt(m):
    try:
        return len(glob.glob(os.path.join("/srv/mail", m, "*.eml")))
    except Exception:
        return 0
ok = cnt("alice") >= 2 and cnt("bob") >= 2 and cnt("dave") >= 2 and cnt("carol") >= 2
print("OK" if ok else "FAIL")
PY
)
if [ "$mbx_ok" = "OK" ]; then points=$((points+25)); fi

# ---- 6. log trail: confirmation record + a deliver-ok line per recipient ----
log_ok=$(python3 - <<'PY'
import os
ok = False
try:
    txt = open("/srv/mail/logs/listmgr.log", encoding="utf-8").read()
    need = ["alice@example.test", "bob@example.test", "dave@example.test", "carol@example.test"]
    lines = txt.splitlines()
    deliver_ok = all(any(("deliver" in ln) and (a in ln) and (" ok" in ln) for ln in lines) for a in need)
    ok = ("subscribed carol@example.test" in txt) and deliver_ok and os.path.isfile("/srv/mail/logs/smtpd.log")
except Exception:
    ok = False
print("OK" if ok else "FAIL")
PY
)
if [ "$log_ok" = "OK" ]; then points=$((points+20)); fi

# fraction 0..1 (reaches 1.0 only when every check passes)
reward=$(python3 -c "print($points / 100.0)")
echo "$reward" > /logs/verifier/reward.txt