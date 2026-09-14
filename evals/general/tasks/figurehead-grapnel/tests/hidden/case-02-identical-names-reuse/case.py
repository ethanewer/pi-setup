#!/usr/bin/env python3
"""Hidden case 2: the SAME folder fetched twice must still reuse the selection.

Usage: case.py <curl-binary>

Fetches the byte-identical mailbox /Projects/ twice in one invocation. The fixed
client must NOT issue a second SELECT (re-selection is skipped for identical
names); a naive "always re-select on IMAP" fix would issue two and fail here.
Both output files must contain the folder's own content.
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
PORT = 28902

MAILBOXES = ["Projects", "Projects"]  # byte-identical names
EXPECT_SELECTS = 1


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
            log.write("\n")
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
                            body = body_for(selected if selected else "Projects")
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
    work = tempfile.mkdtemp(prefix="hc02.")
    transcript = os.path.join(work, "transcript.log")
    try:
        srv = ImapServer(PORT, transcript)
        srv.start()

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
            problems.append("expected %d SELECT command(s) (identical names must reuse the selection), saw %d"
                            % (EXPECT_SELECTS, selects))
        if fetches != len(MAILBOXES):
            problems.append("expected %d FETCH commands, saw %d" % (len(MAILBOXES), fetches))
        for i, mbox in enumerate(MAILBOXES):
            out = os.path.join(work, "out%d" % i)
            with open(out, "rb") as f:
                got = f.read()
            want = body_for(mbox)
            if got != want:
                problems.append("output %d for mailbox %r was %r, expected %r" % (i, mbox, got, want))

        if problems:
            print("FAIL: hidden case 2 (identical names must reuse the selection):")
            for p in problems:
                print("  - " + p)
            print("transcript:\n" + lines)
            return 1
        print("PASS: hidden case 2 (identical names) -- %d SELECT command(s), both outputs correct" % selects)
        return 0
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())