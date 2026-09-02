#!/bin/bash
# Oracle for coral-meridian: write the deliverable client /app/tide.py, boot the
# desk fixture, run the client against the provided fixtures to produce
# /app/peak.json, then shut the desk down. Never reads /tests.
set -eu

CLIENT="/app/tide.py"
OUT="/app/peak.json"

cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""Coral Meridian tide-desk client.

Strictly turn-based: one request line out, one JSON reply line back, per turn.
  tide.py            -> full run; writes the chosen EXTREME reply to /app/peak.json
  tide.py fetch <st> -> HELLO then one READS; prints the raw reply line
"""
import json
import socket
import sys

TOML = "/app/desk/desk.toml"
OUT = "/app/peak.json"


def desk_port():
    try:
        with open(TOML, "rb") as fh:
            raw = fh.read().decode("utf-8", "replace")
        for line in raw.splitlines():
            line = line.strip()
            if line.startswith("port"):
                return int(line.split("=", 1)[1].strip().strip('"'))
    except Exception:
        pass
    return 47231


class Desk:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.sock.settimeout(10)
        self.fh = self.sock.makefile("rwb")

    def ask(self, line):
        """Send ONE request line, read ONE JSON reply line. Never pipeline."""
        self.fh.write((line + "\n").encode("utf-8"))
        self.fh.flush()
        raw = self.fh.readline()
        if not raw:
            raise IOError("desk closed the connection")
        return json.loads(raw.decode("utf-8"))

    def close(self):
        try:
            self.fh.close()
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass


def main():
    args = sys.argv[1:]
    port = desk_port()
    desk = Desk(port)
    try:
        if args and args[0] == "fetch":
            station = args[1]
            hello = desk.ask("HELLO analyst")
            if not hello.get("ok"):
                print(json.dumps(hello))
                return 0
            reply = desk.ask("READS %s" % station)
            print(json.dumps(reply))
            return 0

        hello = desk.ask("HELLO analyst")
        if not hello.get("ok"):
            raise SystemExit("HELLO rejected: %r" % hello)
        best = None  # (value, name)
        for station in hello["desks"]:
            reply = desk.ask("READS %s" % station)
            if not reply.get("ok"):
                raise SystemExit("READS failed for %s: %r" % (station, reply))
            t, v = reply["peak"]
            if best is None or v > best[0] or (v == best[0] and station < best[1]):
                best = (v, station)
        reply = desk.ask("EXTREME %s high" % best[1])
        if not reply.get("ok"):
            raise SystemExit("EXTREME failed: %r" % reply)
        with open(OUT, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(reply) + "\n")
        return 0
    finally:
        desk.close()


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$CLIENT"

# Boot the provided desk, run the client on the visible fixtures, then stop it.
python3 /app/desk/gauge.py &
GAUGE_PID=$!
for i in $(seq 1 40); do
    if python3 -c "import socket,sys; socket.create_connection(('127.0.0.1', 47231), timeout=1).close()" 2>/dev/null; then
        break
    fi
    sleep 0.25
done

python3 "$CLIENT"

kill "$GAUGE_PID" 2>/dev/null || true
wait "$GAUGE_PID" 2>/dev/null || true

echo "solve.sh done -> $CLIENT and $OUT"
ls -l "$CLIENT" "$OUT"
