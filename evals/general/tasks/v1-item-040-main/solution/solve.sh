#!/bin/bash
# Oracle for item-040-main: configure, run, and prove the mail platform workflows.
set -uo pipefail

# ---- Step 1: provisioning + config ----
mkdir -p /srv/mail/alice /srv/mail/bob /srv/mail/admin /srv/mail/carol
mkdir -p /etc/maillists
chmod 700 /srv/mail/alice /srv/mail/bob /srv/mail/admin /srv/mail/carol
cat > /etc/maillists/announce.json <<'EOF'
{"list":"announce","domain":"lists.example.test","subscribers":["alice@example.test","bob@example.test"],"admin":"admin@example.test"}
EOF

# ---- Step 2: start services as background daemons ----
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

def wait_for_msgs(mdir, nmin=1):
    for _ in range(50):
        if len(glob.glob(os.path.join(mdir, "*.eml"))) >= nmin:
            return True
        time.sleep(0.2)
    return True

# confirmation workflow: carol subscribes
send("carol@example.test", "subscribe@lists.example.test",
     "From: carol@example.test\r\nTo: subscribe@lists.example.test\r\nSubject: subscribe me\r\n\r\nrequest\r\n")
time.sleep(1.0)

# find the CONFIRM token in carol's mailbox
token = None
for _ in range(50):
    for p in glob.glob("/srv/mail/carol/*.eml"):
        txt = open(p, encoding="utf-8", errors="replace").read()
        m = re.search(r"Subject: CONFIRM ([0-9a-f]{40})", txt)
        if m:
            token = m.group(1)
            break
    if token:
        break
    time.sleep(0.2)

if not token:
    raise SystemExit("no confirmation token found")

# confirm the subscription (echo token + X-Confirm-Address)
send("carol@example.test", "confirm@lists.example.test",
     "From: carol@example.test\r\nTo: confirm@lists.example.test\r\nSubject: CONFIRM " + token +
     "\r\nX-Confirm-Address: carol@example.test\r\n\r\nconfirm")
wait_for_msgs("/srv/mail/carol")

# delivery workflow: two newsletters
send("admin@example.test", "announce@lists.example.test",
     "From: admin@example.test\r\nTo: announce@lists.example.test\r\nSubject: Newsletter 1\r\n\r\nfirst\r\n")
wait_for_msgs("/srv/mail/alice")
wait_for_msgs("/srv/mail/bob")
wait_for_msgs("/srv/mail/carol")
send("admin@example.test", "announce@lists.example.test",
     "From: admin@example.test\r\nTo: announce@lists.example.test\r\nSubject: Newsletter 2\r\n\r\nsecond")
wait_for_msgs("/srv/mail/alice")
wait_for_msgs("/srv/mail/bob")
wait_for_msgs("/srv/mail/carol")
print("client workflow complete")
PY

python3 /app/client.py
sleep 2
exit 0