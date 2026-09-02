#!/usr/bin/env python3
"""
Basalt Vault maze game service (HTTP/JSON).

Hosts one or more maze instances described by a JSON fixture file.  Each maze
instance is an identity-labelled grid; agents reach it by opening a session
keyed on its id, exploring the unknown grid with /examine + /move, collecting
the treasure, and finally finishing exactly on the exit cell, then /register
to finalize the session before writing the map.

The deliverable /app/grid.py is the CLIENT of this service.  The service is
shipped read-only in the environment so /app/grid.py can be implemented to
match against it exactly.

All calls POST /<endpoint> with a JSON object in the body:
    {"id": "<maze_id>"}                       start/examine/state/finish/register/status
    {"id": "<maze_id>", "r": r, "c": c}       move

Latency matters for agents that explore cell-by-cell; the service is local so
round-trips are sub-millisecond.

Scoring:
    +250  treasure collected (auto when a move lands on the cell)
    +50   finishing on the exit cell
    max   attainable score therefore == 300.
Finishing anywhere other than the exit permanently fails the game (alive=False).

Usage:
    python3 vault_server.py --port PORT [--fixture FIXTURE_JSON]
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TREASURE_BONUS = 250
EXIT_BONUS = 50
MAX_SCORE = TREASURE_BONUS + EXIT_BONUS
GAME = None


def load_fixtures(path):
    with open(path) as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        data = [data]
    return {m["id"]: m for m in data}


class VaultGame:
    def __init__(self, mazes):
        self.mazes = mazes
        self.sessions = {}

    def cell(self, mz, r, c):
        if not (0 <= r < mz["rows"] and 0 <= c < mz["cols"]):
            return "#"
        if [r, c] in mz["walls"]:
            return "#"
        if [r, c] == mz["treasure"]:
            return "T"
        if [r, c] == mz["exit"]:
            return "E"
        return "."

    def start(self, sid):
        mz = self.mazes.get(sid)
        if mz is None:
            return {"ok": False, "error": "unknown_maze"}
        self.sessions[sid] = {"mz": mz, "pos": list(mz["start"]),
                              "collected": False, "finished": False,
                              "alive": True, "registered": False,
                              "score": 0}
        return {"ok": True, "maze_id": sid, "pos": list(mz["start"]),
                "rows": mz["rows"], "cols": mz["cols"]}

    def examine(self, sid):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        r, c = s["pos"]
        return {"ok": True, "pos": [r, c],
                "up": self.cell(s["mz"], r - 1, c),
                "down": self.cell(s["mz"], r + 1, c),
                "left": self.cell(s["mz"], r, c - 1),
                "right": self.cell(s["mz"], r, c + 1),
                "rows": s["mz"]["rows"], "cols": s["mz"]["cols"]}

    def move(self, sid, r, c):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        cr, cc = s["pos"]
        if abs(cr - r) + abs(cc - c) != 1:
            return {"ok": False, "error": "not_adjacent"}
        if not (0 <= r < s["mz"]["rows"] and 0 <= c < s["mz"]["cols"]):
            return {"ok": False, "error": "out_of_bounds"}
        if [r, c] in s["mz"]["walls"]:
            return {"ok": False, "error": "wall"}
        s["pos"] = [r, c]
        if [r, c] == s["mz"]["treasure"] and not s["collected"]:
            s["collected"] = True
        return {"ok": True, "pos": [r, c],
                "cell": self.cell(s["mz"], r, c),
                "collected": s["collected"]}

    def state(self, sid):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        return {"ok": True, "pos": list(s["pos"]),
                "collected": s["collected"], "finished": s["finished"],
                "alive": s["alive"], "score": s["score"],
                "registered": s["registered"]}

    def finish(self, sid):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        er, ec = s["mz"]["exit"]
        if not s["alive"]:
            return {"ok": False, "fail": "game_already_failed"}
        if list(s["pos"]) != [er, ec]:
            s["alive"] = False
            return {"ok": False, "fail": "not_at_exit"}
        s["finished"] = True
        s["score"] = (TREASURE_BONUS if s["collected"] else 0) + EXIT_BONUS
        return {"ok": True, "won": True, "collected": s["collected"],
                "score": s["score"]}

    def register(self, sid):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        s["registered"] = True
        return {"ok": True, "registered": True, "score": s["score"],
                "collected": s["collected"], "finished": s["finished"],
                "alive": s["alive"]}

    def status(self, sid):
        s = self.sessions.get(sid)
        if s is None:
            return {"ok": False, "error": "not_started"}
        return {"ok": True, "pos": list(s["pos"]),
                "collected": s["collected"], "finished": s["finished"],
                "alive": s["alive"], "registered": s["registered"],
                "score": s["score"], "rows": s["mz"]["rows"],
                "cols": s["mz"]["cols"], "exit": list(s["mz"]["exit"]),
                "treasure": list(s["mz"]["treasure"]),
                "start": list(s["mz"]["start"]),
                "walls": [list(w) for w in s["mz"]["walls"]]}


class Handler(BaseHTTPRequestHandler):
    def _reply(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _payload(self):
        try:
            n = int(self.headers.get("Content-Length", 0))
            if n <= 0:
                return {}
            return json.loads(self.rfile.read(n).decode())
        except Exception:
            return {"error": "bad payload"}

    def do_GET(self):
        if self.path == "/ping":
            return self._reply({"ok": True})
        return self._reply({"ok": False, "error": "use_post"})

    def do_POST(self):
        path = self.path.strip("/")
        payload = self._payload()
        if path not in ("start", "examine", "move", "state", "finish",
                        "register", "status"):
            return self._reply({"ok": False, "error": "unknown_endpoint",
                            "path": path})
        if "id" not in payload:
            return self._reply({"ok": False, "error": "missing_id"})
        sid = payload["id"]
        if path == "start":
            out = GAME.start(sid)
        elif path == "examine":
            out = GAME.examine(sid)
        elif path == "move":
            out = GAME.move(sid, payload["r"], payload["c"])
        else:
            out = getattr(GAME, path)(sid)
        return self._reply(out)

    def log_message(self, *a):
        pass


def main():
    global GAME
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8123)
    ap.add_argument("--fixture", default="/app/vault_fixtures.json")
    args = ap.parse_args()
    GAME = VaultGame(load_fixtures(args.fixture))
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"vault-server fixture={args.fixture} on 127.0.0.1:{args.port}",
          flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()