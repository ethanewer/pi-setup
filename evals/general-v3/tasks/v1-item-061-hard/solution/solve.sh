#!/bin/bash
set -euo pipefail

cat > /app/console_server.py <<'PY'
import socket, threading

HOST = "127.0.0.1"
PORT = 2323

def handle(conn):
    try:
        while True:
            data = conn.recv(1024)
            if not data:
                break
            conn.sendall(data)
    except Exception:
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(8)
    print(f"console server listening on {HOST}:{PORT}", flush=True)
    while True:
        conn, _addr = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()

if __name__ == "__main__":
    main()
PY

cat > /app/console_client.py <<'PY'
import socket

HOST = "127.0.0.1"
PORT = 2323

s = socket.create_connection((HOST, PORT), timeout=3)
s.sendall(b"PING\n")
f = s.makefile("rb")
reply = f.readline()
s.close()
print(reply.decode(errors="replace").rstrip("\r\n"))
PY

# Start the server in the background, then exercise the client to confirm.
python3 /app/console_server.py >/tmp/console_server.log 2>&1 &
SERVER_PID=$!
sleep 1
python3 /app/console_client.py
echo "client output above should read: PING"
kill "$SERVER_PID" >/dev/null 2>&1