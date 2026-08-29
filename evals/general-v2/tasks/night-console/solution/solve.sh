#!/bin/bash
set -eu
# Oracle: build the deliverable program (real work), then smoke-run it.
cat > /app/session.py <<'PY'
import sys


def main():
    state = "EMPTY"   # EMPTY | OPEN | CLOSED
    data = {}

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        cmd = parts[0]

        if state == "OPEN":
            if cmd == "CLOSE":
                state = "CLOSED"
                print("CLOSED")
            elif cmd == "OPEN":
                print("ERROR open")
            elif cmd == "PUT":
                if len(parts) < 3:
                    print("ERROR bad")
                else:
                    data[parts[1]] = parts[2]
                    print("OK")
            elif cmd == "GET":
                if len(parts) < 2:
                    print("ERROR bad")
                else:
                    print("VALUE " + data[parts[1]]
                          if parts[1] in data else "ERROR missing")
            elif cmd == "LIST":
                keys = list(sorted(data))
                print("KEYS" + ((" " + ",".join(keys)) if keys else ""))
            else:
                print("ERROR unknown")
        elif state == "CLOSED":
            # Name check first (documented precedence): an unrecognised name
            # still answers ERROR unknown; recognised commands are all rejected.
            if cmd in ("OPEN", "PUT", "GET", "LIST", "CLOSE"):
                print("ERROR not open")
            else:
                print("ERROR unknown")
        else:  # EMPTY
            if cmd == "OPEN":
                if len(parts) < 2:
                    print("ERROR bad")
                else:
                    state = "OPEN"
                    print("OK")
            elif cmd in ("PUT", "GET", "LIST", "CLOSE"):
                print("ERROR not open")
            else:
                print("ERROR unknown")


if __name__ == "__main__":
    main()
PY
chmod +x /app/session.py

# Smoke-run the deliverable so we know it executes and honours the contract.
printf 'OPEN demo\nPUT k v\nLIST\nGET k\nCLOSE\nGET k\n' \
  | python3 /app/session.py >/tmp/smoke.out
grep -q '^VALUE v$' /tmp/smoke.out