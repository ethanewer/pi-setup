#!/bin/bash
# Oracle for basalt-maze: author the /app/dispatch.py client (real BFS route
# planner + one-request-per-connection navd driver), start the depot's navd on
# the default grid, run the client to produce /app/route.json, and sanity-check
# it. Never reads /tests.
set -euo pipefail
cd /app

# ---- 1. Deliverable /app/dispatch.py : the navd client ----
cat > /app/dispatch.py <<'PY'
#!/usr/bin/env python3
"""basalt-maze crawler dispatcher.

Usage: python3 /app/dispatch.py <port> <output_json>

Connects to the navd daemon on 127.0.0.1:<port>, sends PLAN, computes a
wall-avoiding route from start to goal, then issues STEP commands (exactly
one text request per connection, as the daemon requires) until the crawler
arrives. Writes the dispatch result JSON to <output_json>.

If the goal is unreachable the program prints a diagnostic to stderr, exits
non-zero and does NOT create the output file.
"""
import hashlib
import json
import socket
import sys
from collections import deque

HOST = "127.0.0.1"
STEP_OF = {(-1, 0): "N", (1, 0): "S", (0, 1): "E", (0, -1): "W"}


def request(port, command, timeout=10.0):
    """One navd request = one connection: send one text line, read one JSON."""
    sock = socket.create_connection((HOST, port), timeout=timeout)
    try:
        sock.sendall((command.rstrip("\n") + "\n").encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
    finally:
        try:
            sock.close()
        except OSError:
            pass
    line = buf.split(b"\n", 1)[0].decode("utf-8", "replace").strip()
    if not line:
        raise IOError("empty reply from navd for %r" % command)
    return json.loads(line)


def bfs(rows, cols, walls, start, goal):
    """Shortest wall-avoiding step list, or None if unreachable."""
    if start == goal:
        return []
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        if cur == goal:
            break
        for dr, dc in ((-1, 0), (1, 0), (0, 1), (0, -1)):
            nxt = (cur[0] + dr, cur[1] + dc)
            if (0 <= nxt[0] < rows and 0 <= nxt[1] < cols
                    and nxt not in walls and nxt not in prev):
                prev[nxt] = cur
                q.append(nxt)
    if goal not in prev:
        return None
    steps = []
    cur = goal
    while prev[cur] is not None:
        pr = prev[cur]
        steps.append(STEP_OF[(cur[0] - pr[0], cur[1] - pr[1])])
        cur = pr
    steps.reverse()
    return steps


def main():
    if len(sys.argv) != 3:
        print("usage: dispatch.py <port> <output_json>", file=sys.stderr)
        return 2
    port, out_path = int(sys.argv[1]), sys.argv[2]

    plan = request(port, "PLAN")
    if not plan.get("ok"):
        print("PLAN rejected: %s" % plan, file=sys.stderr)
        return 4
    rows, cols = plan["grid"]["rows"], plan["grid"]["cols"]
    start = (plan["start"]["row"], plan["start"]["col"])
    goal = (plan["goal"]["row"], plan["goal"]["col"])
    walls = {(w[0], w[1]) for w in plan.get("walls", [])}

    steps = bfs(rows, cols, walls, start, goal)
    if steps is None:
        print("goal %s is unreachable from %s" % (goal, start),
              file=sys.stderr)
        return 3

    token = plan.get("token")  # present on PLAN iff start == goal
    pos = start
    for direction in steps:
        resp = request(port, "STEP " + direction)
        if not resp.get("ok"):
            print("STEP %s rejected: %s" % (direction, resp), file=sys.stderr)
            return 4
        pos = (resp["pos"]["row"], resp["pos"]["col"])
        if resp.get("status") == "arrived":
            token = resp.get("token")
            break
    if pos != goal:
        print("crawler ended at %s, not at goal %s" % (pos, goal),
              file=sys.stderr)
        return 5

    result = {
        "grid": plan["grid"],
        "start": {"row": start[0], "col": start[1]},
        "goal": {"row": goal[0], "col": goal[1]},
        "steps": steps,
        "final": {"row": pos[0], "col": pos[1]},
        "moves": len(steps),
        "token": token,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod 0755 /app/dispatch.py

# ---- 2. Start the depot's navd on the default grid and dispatch ----
pkill -f "navd.py /app/navd/grid.json" 2>/dev/null || true
sleep 0.2
python3 /app/navd/navd.py /app/navd/grid.json 43770 > /tmp/oracle_navd.log 2>&1 &
NAVD_PID=$!
for _ in $(seq 1 40); do
    grep -q LISTENING /tmp/oracle_navd.log 2>/dev/null && break
    sleep 0.25
done
grep -q LISTENING /tmp/oracle_navd.log || { echo "navd did not start"; exit 1; }

python3 /app/dispatch.py 43770 /app/route.json
RC=$?
kill "$NAVD_PID" 2>/dev/null || true

test -f /app/route.json || { echo "missing /app/route.json"; exit 1; }
python3 - <<'PY'
import hashlib, json
r = json.load(open("/app/route.json"))
s = "navd-v1|%dx%d|%d,%d|%d" % (r["grid"]["rows"], r["grid"]["cols"],
                                r["final"]["row"], r["final"]["col"],
                                r["moves"])
want = hashlib.sha256(s.encode()).hexdigest()[:40]
assert r["token"] == want, (r["token"], want)
assert (r["final"]["row"], r["final"]["col"]) == \
       (r["goal"]["row"], r["goal"]["col"]), r["final"]
print("oracle ok: dispatched in", r["moves"], "steps")
PY
echo "solve.sh done -> /app/dispatch.py and /app/route.json"
