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
    for p in glob.glob("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40b/srv/mail/carol/*.eml"):
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