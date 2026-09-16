#!/usr/bin/env bash
# reproduce_bug.sh -- reproduce curl's silent wrong-mailbox IMAP fetch (issue #22868)
#
# Usage: reproduce_bug.sh [PATH-TO-CURL-BINARY]
#   default binary: /app/curl/src/curl
#
# Runs a local IMAP server on 127.0.0.1 (any port) that logs every client command,
# then fetches TWO IMAP URLs in a single curl invocation whose mailboxes differ ONLY
# by letter case, and inspects the server-side transcript.
#
# Exit status:
#   0  the curl under test issued a fresh mailbox-selection command (SELECT)
#      for the second, case-differing mailbox -- correct behaviour
#   1  the second fetch proceeded while the first mailbox was still selected
set -u

CURL_BIN="${1:-/app/curl/src/curl}"
PORT="${IMAP_TEST_PORT:-18893}"
WORK=$(mktemp -d /tmp/imaprepro.XXXXXX) || exit 1
TRANSCRIPT="$WORK/transcript.log"
SERVER_LOG="$WORK/server.log"
SERVER_PID=""

cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$WORK" 2>/dev/null
    return 0
}
trap cleanup EXIT

# minimal IMAP server; logs every client command to $TRANSCRIPT
python3 - "$PORT" "$TRANSCRIPT" >>"$SERVER_LOG" 2>&1 <<'PYEOF' &
import socket, threading, re, sys

PORT = int(sys.argv[1])
LOG = open(sys.argv[2], "a", buffering=1)

def send(c, data):
    c.sendall(data.encode("utf-8") if isinstance(data, str) else data)

def handle(conn):
    conn.settimeout(30)
    send(conn, "* OK IMAP server ready\r\n")
    buf = b""
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break
            buf += data
            while b"\r\n" in buf:
                line, buf = buf.split(b"\r\n", 1)
                text = line.decode("utf-8", "replace")
                LOG.write(text + "\n")
                m = re.match(r"^(A\d+)\s+([A-Za-z]+)(?:\s+(.*))?$", text)
                if not m:
                    send(conn, "* BAD\r\n")
                    continue
                tag, cmd, rest = m.group(1), m.group(2).upper(), (m.group(3) or "").strip()
                if cmd == "CAPABILITY":
                    send(conn, "* CAPABILITY IMAP4rev1\r\n")
                    send(conn, tag + " OK CAPABILITY completed\r\n")
                elif cmd == "LOGIN":
                    send(conn, tag + " OK LOGIN completed\r\n")
                elif cmd == "SELECT":
                    send(conn, "* 172 EXISTS\r\n* 1 RECENT\r\n")
                    send(conn, "* OK [UNSEEN 12] Message 12 is first unseen\r\n")
                    send(conn, "* OK [UIDVALIDITY 3857529045] UIDs valid\r\n")
                    send(conn, "* OK [UIDNEXT 4392] Predicted next UID\r\n")
                    send(conn, "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n")
                    send(conn, "* OK [PERMANENTFLAGS (\\Deleted \\Seen \\*)] Limited\r\n")
                    send(conn, tag + " OK [READ-WRITE] SELECT completed\r\n")
                elif cmd == "FETCH":
                    parts = rest.split(" ", 1)
                    num = parts[0] if parts else "1"
                    how = parts[1] if len(parts) > 1 else "BODY[]"
                    body = b"body of the message\r\n"
                    send(conn, "* %s FETCH (%s {%d}\r\n" % (num, how, len(body)))
                    send(conn, body)
                    send(conn, ")\r\n")
                    send(conn, tag + " OK FETCH completed\r\n")
                elif cmd == "LOGOUT":
                    send(conn, "* BYE curl IMAP server signing off\r\n")
                    send(conn, tag + " OK LOGOUT completed\r\n")
                    conn.close()
                    return
                else:
                    send(conn, tag + " BAD Command\r\n")
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", PORT))
s.listen(8)
print("READY", flush=True)
while True:
    c, _ = s.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PYEOF
SERVER_PID=$!

# wait for the server to accept connections
ready=0
for _ in $(seq 1 100); do
    if python3 -c "import socket; s=socket.socket(); s.settimeout(0.5); s.connect(('127.0.0.1', $PORT)); s.close()" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 0.1
done
if [ "$ready" != "1" ]; then
    echo "IMAP server did not start"
    cat "$SERVER_LOG"
    exit 1
fi

# two fetches in ONE invocation, mailboxes differ only by letter case
"$CURL_BIN" -s -o /dev/null --max-time 60 -u user:secret \
    "imap://127.0.0.1:$PORT/Private/;MAILINDEX=123/;SECTION=1" \
    -o /dev/null \
    "imap://127.0.0.1:$PORT/private/;MAILINDEX=456/;SECTION=2.3" 2>"$WORK/curl.err"
rc=$?

# give the server a moment to flush the final commands
sleep 0.3

selects=$(grep -c -E '^A[0-9]+ SELECT ' "$TRANSCRIPT" 2>/dev/null || true)
[ -n "$selects" ] || selects=0

if [ "$rc" -ne 0 ]; then
    echo "FAIL: curl exited $rc"
    cat "$WORK/curl.err" 2>/dev/null
    echo "transcript:"
    cat "$TRANSCRIPT"
    exit 1
fi

if [ "$selects" -ge 2 ]; then
    echo "PASS: the curl under test issued $selects SELECT command(s); the second case-differing mailbox was selected explicitly"
    exit 0
else
    echo "BUG REPRODUCED: two case-differing mailboxes but only $selects SELECT command(s) on the wire; the second fetch reused the first mailbox"
    echo "transcript:"
    cat "$TRANSCRIPT"
    exit 1
fi