#!/usr/bin/env python3
"""Minimal SMTP server (local MTA) for the mailing-list platform.

Serves the domains example.test (local maildir delivery) and lists.example.test
(list intake queue). Listens on 127.0.0.1:2525 by default.

Rules:
  * rcpt ending @lists.example.test  -> append message to /srv/list/queue/ (250)
  * rcpt ending @example.test        -> local delivery into /srv/mail/<local>/
                                         (one <seq>.<mid>.eml file per message).
                                         If /srv/mail/<local> does not exist -> 550
                                         and log "delivery_failed".
  * any other domain                -> 550 rejected.
Logs every accepted message to /Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs/smtpd.log.
"""
import argparse
import os
import re
import socketserver
import sys
import time

HOST = "127.0.0.1"
PORT = 2525
LIST_QUEUE = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/list/queue"
MAIL_ROOT = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail"
LOG_PATH = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs/smtpd.log"

def log(line):
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")

def next_seq():
    os.makedirs("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs", exist_ok=True)
    seqfile = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs/counter"
    n = 0
    try:
        with open(seqfile) as f:
            n = int(f.read().strip())
    except Exception:
        pass
    with open(seqfile, "w") as f:
        f.write(str(n + 1))
    return n + 1

def accept_domain(domain):
    return domain in ("example.test", "lists.example.test")

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"220 mail.example.test ESMTP\r\n")
        self.wfile.flush()
        mail_from = None
        rcpts = []
        data_mode = False
        msg_lines = []
        while True:
            line = self.rfile.readline()
            if not line:
                break
            if data_mode:
                if line.strip() == b".":
                    data_mode = False
                    self._deliver(mail_from, rcpts, msg_lines)
                    msg_lines = []
                    self.wfile.write(b"250 OK: queued\r\n")
                    self.wfile.flush()
                    mail_from = None
                    rcpts = []
                else:
                    msg_lines.append(line)
                continue
            raw = line.strip().decode("utf-8", "replace")
            upper = raw.upper()
            if upper.startswith(("EHLO", "HELO")):
                self.wfile.write(b"250 mail.example.test\r\n")
            elif upper.startswith("MAIL FROM:"):
                m = re.search(r"<([^>]*)>", raw)
                mail_from = m.group(1) if m else ""
                self.wfile.write(b"250 OK\r\n")
            elif upper.startswith("RCPT TO:"):
                m = re.search(r"<([^>]*)>", raw)
                if not m:
                    self.wfile.write(b"501 malformed\r\n")
                    continue
                rcpt = m.group(1).lower()
                domain = rcpt.split("@")[-1].lower()
                if accept_domain(domain):
                    rcpts.append(rcpt)
                    self.wfile.write(b"250 OK\r\n")
                else:
                    self.wfile.write(b"550 relay not permitted\r\n")
            elif upper.startswith("DATA"):
                if not rcpts:
                    self.wfile.write(b"503 no recipients\r\n")
                    continue
                data_mode = True
                self.wfile.write(b"354 go ahead\r\n")
            elif upper == "RSET":
                mail_from = None; rcpts = []
                self.wfile.write(b"250 OK\r\n")
            elif upper == "QUIT":
                self.wfile.write(b"221 bye\r\n")
                self.wfile.flush()
                break
            else:
                self.wfile.write(b"250 OK\r\n")
            self.wfile.flush()

    def _deliver(self, mail_from, rcpts, msg_lines):
        mid = "m%d" % next_seq()
        body = b"".join(msg_lines)
        for rcpt in rcpts:
            domain = rcpt.split("@")[-1]
            if domain == "lists.example.test":
                os.makedirs(LIST_QUEUE, exist_ok=True)
                path = os.path.join(LIST_QUEUE, "%s.%s.eml" % (mid, re.sub(r"[^A-Za-z0-9]", "", rcpt)))
                with open(path, "wb") as f:
                    f.write(b"X-Envelope-Rcpt: " + rcpt.encode() + b"\r\n")
                    f.write(b"X-Envelope-From: " + (mail_from or "").encode() + b"\r\n")
                    f.write(body)
                    if body and not body.endswith(b"\n"):
                        f.write(b"\n")
                log("accepted %s %s" % (mid, rcpt))
            else:
                local = rcpt.split("@")[0]
                mdir = os.path.join(MAIL_ROOT, local)
                if os.path.isdir(mdir):
                    with open(os.path.join(mdir, "%s.eml" % mid), "wb") as f:
                        f.write(body)
                    log("accepted %s %s" % (mid, rcpt))
                else:
                    log("delivery_failed %s %s" % (local, mid))

class ThreadingSMTP(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=PORT)
    args = ap.parse_args()
    os.makedirs(LIST_QUEUE, exist_ok=True)
    os.makedirs(MAIL_ROOT, exist_ok=True)
    os.makedirs("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m40/srv/mail/logs", exist_ok=True)
    log("smtpd started port=%d pid=%d" % (args.port, os.getpid()))
    with ThreadingSMTP((HOST, args.port), Handler) as srv:
        srv.serve_forever()

if __name__ == "__main__":
    main()