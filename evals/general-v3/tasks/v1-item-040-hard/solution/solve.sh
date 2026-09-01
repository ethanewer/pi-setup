#!/bin/bash
# Oracle for item-040-hard: provision missing Maildirs, run both services,
# drive confirmation + recovery campaign + member-covering campaign.
set -uo pipefail

# ---- Step 1: provision the two missing Maildirs BEFORE starting services ----
mkdir -p /srv/mail/dave /srv/mail/carol
chmod 700 /srv/mail/dave /srv/mail/carol

# ---- Step 2: start both daemons as long-running background processes ----
mkdir -p /srv/mail/logs
if ! pgrep -f "mailplatform/mailservice.py" >/dev/null 2>&1; then
  nohup python3 /app/mailplatform/mailservice.py --port 2525 >> /srv/mail/logs/smtpd.log 2>&1 &
fi
if ! pgrep -f "mailplatform/listmgr.py" >/dev/null 2>&1; then
  nohup python3 /app/mailplatform/listmgr.py >> /srv/mail/logs/listmgr.log 2>&1 &
fi
sleep 1

cat > /app/client.py <<'PY'
import smtplib, time, re, os, glob

def send(frm, rcpt, data):
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as s:
        s.sendmail(frm, [rcpt], data)

def wait_msgs(mdir, nmin=1):
    for _ in range(100):
        if len(glob.glob(os.path.join(mdir, "*.eml"))) >= nmin:
            return True
        time.sleep(0.2)
    return False

# Campaign 1: two posts covering the current subscribers (alice, bob, dave).
for _ in range(2):
    send("admin@example.test", "announce@lists.example.test",
         "From: admin@example.test\r\nTo: announce@lists.example.test\r\n"
         "Subject: Member briefing\r\n\r\nMKT-ALPHA-1 recovery briefing\r\n")
time.sleep(1.0)
wait_msgs("/srv/mail/alice", 2)
wait_msgs("/srv/mail/bob", 2)
wait_msgs("/srv/mail/dave", 2)

# Confirmation workflow for the new member carol.
send("carol@example.test", "subscribe@lists.example.test",
     "From: carol@example.test\r\nTo: subscribe@lists.example.test\r\n"
     "Subject: subscribe me\r\n\r\nrequest\r\n")
time.sleep(1.0)
token = None
for _ in range(100):
    for p in glob.glob("/srv/mail/carol/*.eml"):
        txt = open(p, encoding="utf-8", errors="replace").read()
        m = re.search(r"Subject: CONFIRM ([0-9a-f]{40})", txt)
        if m:
            token = m.group(1); break
    if token: break
    time.sleep(0.2)
assert token, "no confirmation token found"

send("carol@example.test", "confirm@lists.example.test",
     "From: carol@example.test\r\nTo: confirm@lists.example.test\r\n"
     "Subject: CONFIRM " + token +
     "\r\nX-Confirm-Address: carol@example.test\r\n\r\nconfirm")
time.sleep(1.0)
wait_msgs("/srv/mail/carol", 2)   # welcome + (future campaign kept to 1 here)

# Campaign 2: now also covers the newly-confirmed carol.
send("admin@example.test", "announce@lists.example.test",
     "From: admin@example.test\r\nTo: announce@lists.example.test\r\n"
     "Subject: Member briefing\r\n\r\nMKT-BETA2\r\n")
time.sleep(1.0)
wait_msgs("/srv/mail/alice", 3)
wait_msgs("/srv/mail/bob", 3)
wait_msgs("/srv/mail/dave", 3)
wait_msgs("/srv/mail/carol", 2)
print("hard workflow complete")
PY

python3 /app/client.py
sleep 2
exit 0