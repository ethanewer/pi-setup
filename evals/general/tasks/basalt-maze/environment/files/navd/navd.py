#!/usr/bin/env python3
"""navd — warehouse crawler navigation daemon (fixture service).

Raw TCP text protocol on 127.0.0.1. Line-based: the client sends ONE text
command line; navd answers with ONE JSON line and then CLOSES the connection.
Exactly one request per connection — pipelined requests are ignored.

Usage:
    python3 navd.py <grid.json> <port>
    (port 0 => pick a free port; the daemon prints "LISTENING <port>" on
     stdout once it is ready)

Commands:
    PLAN            -> {"ok":true,"grid":{"rows":R,"cols":C},
                        "start":{"row":r,"col":c},"goal":{"row":r,"col":c},
                        "walls":[[r,c],...]
                        [,"status":"arrived","moves":0,"token":"<40hex>"]}
                      Resets the crawler to the start cell. If start == goal
                      the reply also carries "status":"arrived", "moves":0 and
                      the arrival "token".

    STEP <dir>      -> {"ok":true,"status":"moving"|"arrived"|"blocked",
                        "pos":{"row":r,"col":c},"moves":n
                        [,"token":"<40hex>"]}
                      dir is one of N, S, E, W. "blocked" means the crawler
                      stayed in place (wall or grid edge); the move still
                      counts. When status is "arrived" the reply carries the
                      arrival "token".

    anything else   -> {"ok":false,"error":"..."}

Arrival token formula (deterministic, verified by the grader):
    sha256("navd-v1|<rows>x<cols>|<row>,<col>|<moves>").hexdigest()[:40]
where <row>,<col> is the FINAL crawler position and <moves> is the number of
STEP commands the crawler issued to get there.

After MOVE_LIMIT total STEP commands the daemon answers
    {"ok":false,"error":"move-limit"}
"""
import hashlib
import json
import socket
import sys

MOVE_LIMIT = 4096
DIRS = {"N": (-1, 0), "S": (1, 0), "E": (0, 1), "W": (0, -1)}


def session_token(rows, cols, row, col, moves):
    s = "navd-v1|%dx%d|%d,%d|%d" % (rows, cols, row, col, moves)
    return hashlib.sha256(s.encode()).hexdigest()[:40]


class Session:
    def __init__(self, grid):
        self.rows = int(grid["rows"])
        self.cols = int(grid["cols"])
        self.start = (int(grid["start"][0]), int(grid["start"][1]))
        self.goal = (int(grid["goal"][0]), int(grid["goal"][1]))
        self.walls = set((int(w[0]), int(w[1])) for w in grid.get("walls", []))
        self.reset()

    def reset(self):
        self.pos = self.start
        self.moves = 0
        self.arrived = (self.pos == self.goal)


def handle(sess, line):
    try:
        parts = line.strip().split()
        if not parts:
            return {"ok": False, "error": "empty-request"}
        name = parts[0].upper()

        if name == "PLAN":
            sess.reset()
            reply = {
                "ok": True,
                "grid": {"rows": sess.rows, "cols": sess.cols},
                "start": {"row": sess.start[0], "col": sess.start[1]},
                "goal": {"row": sess.goal[0], "col": sess.goal[1]},
                "walls": [[r, c] for r, c in sorted(sess.walls)],
            }
            if sess.arrived:
                reply["status"] = "arrived"
                reply["moves"] = 0
                reply["token"] = session_token(
                    sess.rows, sess.cols, sess.pos[0], sess.pos[1], 0)
            return reply

        if name == "STEP":
            if sess.arrived:
                return {"ok": False, "error": "already-arrived"}
            if len(parts) != 2 or parts[1].upper() not in DIRS:
                return {"ok": False, "error": "bad-direction"}
            if sess.moves >= MOVE_LIMIT:
                return {"ok": False, "error": "move-limit"}
            dr, dc = DIRS[parts[1].upper()]
            sess.moves += 1
            nr, nc = sess.pos[0] + dr, sess.pos[1] + dc
            if not (0 <= nr < sess.rows and 0 <= nc < sess.cols) \
                    or (nr, nc) in sess.walls:
                status = "blocked"
            else:
                sess.pos = (nr, nc)
                status = "arrived" if sess.pos == sess.goal else "moving"
                if status == "arrived":
                    sess.arrived = True
            reply = {
                "ok": True,
                "status": status,
                "pos": {"row": sess.pos[0], "col": sess.pos[1]},
                "moves": sess.moves,
            }
            if sess.arrived:
                reply["token"] = session_token(
                    sess.rows, sess.cols, sess.pos[0], sess.pos[1], sess.moves)
            return reply

        return {"ok": False, "error": "unknown-command"}
    except Exception:
        return {"ok": False, "error": "bad-request"}


def serve(grid_path, port):
    with open(grid_path, "r", encoding="utf-8") as fh:
        sess = Session(json.load(fh))
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(16)
    actual = srv.getsockname()[1]
    print("LISTENING %d" % actual, flush=True)
    while True:
        try:
            conn, _ = srv.accept()
        except OSError:
            break
        try:
            conn.settimeout(10)
            buf = b""
            while b"\n" not in buf and len(buf) < 8192:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
            line = buf.split(b"\n", 1)[0].decode("utf-8", "replace")
            reply = handle(sess, line)
            conn.sendall((json.dumps(reply) + "\n").encode("utf-8"))
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: navd.py <grid.json> <port>", file=sys.stderr)
        sys.exit(2)
    serve(sys.argv[1], int(sys.argv[2]))
