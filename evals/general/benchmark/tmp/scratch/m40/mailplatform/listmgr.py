#!/usr/bin/env python3
"""Mailman-style list manager daemon for the mailing-list platform.

Watches /srv/list/queue/ for incoming list-addressed emails and routes them:

  localpart == "subscribe"  -> send a confirmation email back to the sender.
                               Subject:  CONFIRM <sha1hex(tokenmaterial)>
                               Header:   X-Confirm-Address: <sender email>
                               Log:      confirm_sent <email> <token>
  localpart == "confirm"    -> subject is "CONFIRM <token>"; validates the token
                               against X-Confirm-Address, then appends that
                               address to /srv/mail/confirmed.txt and sends a
                               welcome email. Log: subscribed <email>
  anything else             -> a normal post: send a copy of the message to every
                               subscriber (config subscribers + confirmed.txt).
                               Log per subscriber: deliver <msgid> <addr> ok
                               or delivery_failed <addr> <msgid> on SMTP refusal.

Processed messages are renamed to <name>.done. All logs to listmgr.log.
"""
import hashlib
import os
import re
import smtplib
import sys
import time

LIST_QUEUE = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/list/queue"
CONFIG = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/etc/maillists/announce.json"
CONFIRMED = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/confirmed.txt"
LOG_PATH = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs/listmgr.log"
SMTP_PORT = 2525

def log(line):
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")

def load_config():
    import json
    with open(CONFIG) as f:
        return json.load(f)

def confirmed_addrs():
    addrs = []
    if os.path.exists(CONFIRMED):
        for line in open(CONFIRMED):
            line = line.strip()
            if line:
                addrs.append(line)
    return addrs

def token_of(email):
    return hashlib.sha1(("mailinglist:" + email + ":secret").encode()).hexdigest()

def send(subject, to_addr, from_addr, body):
    msg = ("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain\r\n\r\n%s\r\n"
           % (from_addr, to_addr, subject, body))
    with smtplib.SMTP("127.0.0.1", SMTP_PORT, timeout=3) as s:
        s.sendmail(from_addr, [to_addr], msg)

def process_one(path, cfg):
    name = os.path.basename(path)
    text = open(path, "rb").read().decode("utf-8", "replace")
    env_rcpt = re.search(r"^X-Envelope-Rcpt: ?(.+?)\r?$", text, re.M).group(1).strip()
    env_from = re.search(r"^X-Envelope-From: ?(.*?)\r?$", text, re.M).group(1).strip()
    local = env_rcpt.split("@")[0].lower()
    msgid = name.split(".")[0]

    if local == "subscribe":
        token = token_of(env_from)
        subject = "CONFIRM %s" % token
        send(subject, env_from, "listmaster@example.test",
             "Reply with subject: CONFIRM %s" % token)
        log("confirm_sent %s %s" % (env_from, token))
        return True

    if local == "confirm":
        m = re.search(r"CONFIRM ([0-9a-f]{40})", text)
        xaddr = re.search(r"^X-Confirm-Address: ?(.+?)\r?$", text, re.M)
        if not m or not xaddr:
            log("confirm_rejected malformed %s" % msgid)
            return True
        token = m.group(1)
        email = xaddr.group(1).strip().lower()
        if token_of(email) != token:
            log("confirm_rejected token %s" % email)
            return True
        with open(CONFIRMED, "a") as f:
            f.write(email + "\n")
        send("Welcome to announce", email, "listmaster@example.test",
             "You are now subscribed to announce.")
        log("subscribed %s" % email)
        return True

    # normal post
    subs = list(cfg.get("subscribers", []))
    subs.extend(confirmed_addrs())
    ok = True
    for addr in subs:
        addr = addr.strip().lower()
        if not addr:
            continue
        try:
            send("announce: " + name, addr, "announce@lists.example.test", "list post body")
            log("deliver %s %s ok" % (msgid, addr))
        except Exception as e:
            log("delivery_failed %s %s" % (addr, msgid))
            ok = False
    return True

def main():
    log("listmgr started pid=%d" % os.getpid())
    seen = set()
    while True:
        try:
            files = sorted(f for f in os.listdir(LIST_QUEUE) if f.endswith(".eml"))
            for f in files:
                path = os.path.join(LIST_QUEUE, f)
                if path in seen:
                    continue
                cfg = load_config()
                process_one(path, cfg)
                seen.add(path)
                os.rename(path, path + ".done")
        except Exception as e:
            log("error %s" % repr(e))
        time.sleep(0.2)

if __name__ == "__main__":
    main()