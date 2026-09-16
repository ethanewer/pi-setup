#!/usr/bin/env python3
"""Hidden case 1: THREE case-variants of one folder in a single invocation.

Usage: case.py <curl-binary>

Fetches /Private/, /private/ and /PRIVATE/ (plus a per-URL -o file) in one curl
invocation against a local IMAP server that serves distinct content per mailbox.
Requires the fixed client to SELECT each case-differing mailbox explicitly
(3 SELECT commands) and each output file to contain exactly its own mailbox's
content. On the pre-fix client the second and third fetches silently reuse the
first mailbox, so both the transcript count and the file contents differ.
Exit 0 = pass, nonzero = fail.
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time

CURL = sys.argv[1] if len(sys.argv) > 1 else "/app/curl/src/curl"
PORT = 28901

MAILBOXES = ["Private", "private", "PRIVATE"]  # differ ONLY by letter case
EXPECT_SELECTS = len(MAILBOXES)


def body_for(mbox):
    return ("mail from %s\r\n" % mbox).encode()


class ImapServer(threading.Thread):
    def __init__(self, port, transcript):
        super().__init__(daemon=True)
        self.transcript = transcript
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", port))
        self.sock.listen(8)
        self.sock.settimeout(0.5)

    def run(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _send(self, conn, data):
        conn.sendall(data.encode() if isinstance(data, str) else data)

    def _handle(self, conn):
        selected = None
        with open(self.transcript, "a") as log:
            log.write("\n")  # separate connections
            try:
                self._send(conn, "* OK IMAP server ready\r\n")
                buf = b""
                while True:
                    data = conn.recv(4096)
                    if not data:
                        break
                    buf += data
                    while b"\r\n" in buf:
                        line, buf = buf.split(b"\r\n", 1)
                        text = line.decode("utf-8", "replace")
                        log.write(text + "\n")
                        log.flush()
                        m = re.match(r"^(A\d+)\s+([A-Za-z]+)(?:\s+(.*))?$", text)
                        if not m:
                            self._send(conn, "* BAD\r\n")
                            continue
                        tag, cmd, rest = m.group(1), m.group(2).upper(), (m.group(3) or "").strip()
                        if cmd == "CAPABILITY":
                            self._send(conn, "* CAPABILITY IMAP4rev1\r\n")
                            self._send(conn, tag + " OK CAPABILITY completed\r\n")
                        elif cmd == "LOGIN":
                            self._send(conn, tag + " OK LOGIN completed\r\n")
                        elif cmd == "SELECT":
                            mbox = rest.split(" ", 1)[0].strip('"')
                            selected = mbox
                            self._send(conn, "* 172 EXISTS\r\n* 1 RECENT\r\n")
                            self._send(conn, "* OK [UNSEEN 12] Message 12 is first unseen\r\n")
                            self._send(conn, "* OK [UIDVALIDITY 3857529045] UIDs valid\r\n")
                            self._send(conn, "* OK [UIDNEXT 4392] Predicted next UID\r\n")
                            self._send(conn, "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")
                            self._send(conn, "* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n")
                            self._send(conn, tag + " OK [READ-WRITE] SELECT completed\r\n")
                        elif cmd == "FETCH":
                            parts = rest.split(" ", 1)
                            num = parts[0] if parts else "1"
                            how = parts[1] if len(parts) > 1 else "BODY[]"
                            body = body_for(selected if selected else "private")
                            self._send(conn, "* %s FETCH (%s {%d}\r\n" % (num, how, len(body)))
                            self._send(conn, body)
                            self._send(conn, ")\r\n")
                            self._send(conn, tag + " OK FETCH completed\r\n")
                        elif cmd == "LOGOUT":
                            self._send(conn, "* BYE curl IMAP server signing off\r\n")
                            self._send(conn, tag + " OK LOGOUT completed\r\n")
                            conn.close()
                            return
                        else:
                            self._send(conn, tag + " BAD Command\r\n")
            except OSError:
                pass
            finally:
                try:
                    conn.close()
                except OSError:
                    pass


def main():
    work = tempfile.mkdtemp(prefix="hc01.")
    transcript = os.path.join(work, "transcript.log")
    try:
        srv = ImapServer(PORT, transcript)
        srv.start()

        # wait for the server socket to be ready
        for _ in range(100):
            try:
                s = socket.socket()
                s.settimeout(0.3)
                s.connect(("127.0.0.1", PORT))
                s.close()
                break
            except OSError:
                time.sleep(0.1)
        else:
            print("FAIL: IMAP server did not start")
            return 1

        argv = [CURL, "-s"]
        for i, mbox in enumerate(MAILBOXES):
            out = os.path.join(work, "out%d" % i)
            argv += ["-o", out,
                     "imap://127.0.0.1:%d/%s/;MAILINDEX=%d/;SECTION=1"
                     % (PORT, mbox, 101 + 101 * i)]
        argv += ["-u", "user:secret", "--max-time", "60"]
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.5)

        if proc.returncode != 0:
            print("FAIL: curl exited %d\n%s" % (proc.returncode, proc.stderr.decode()))
            return 1

        with open(transcript) as lf:
            lines = lf.read()
        selects = len(re.findall(r"^A\d+ SELECT ", lines, re.M))
        fetches = len(re.findall(r"^A\d+ FETCH ", lines, re.M))

        problems = []
        if selects != EXPECT_SELECTS:
            problems.append("expected %d SELECT commands, saw %d (transcript below)" % (EXPECT_SELECTS, selects))
        if fetches != len(MAILBOXES):
            problems.append("expected %d FETCH commands, saw %d" % (len(MAILBOXES), fetches))
        for i, mbox in enumerate(MAILBOXES):
            out = os.path.join(work, "out%d" % i)
            with open(out, "rb") as f:
                got = f.read()
            want = body_for(mbox)
            if got != want:
                problems.append("output %d for mailbox %r was %r, expected %r (fetched from a different folder?)"
                                % (i, mbox, got, want))

        if problems:
            print("FAIL: hidden case 1 (three case-variants):")
            for p in problems:
                print("  - " + p)
            print("transcript:\n" + lines)
            return 1
        print("PASS: hidden case 1 (three case-variants) -- %d SELECT commands, all %d outputs from their own mailboxes"
              % (selects, len(MAILBOXES)))
        return 0
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())