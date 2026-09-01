#!/usr/bin/env python3
"""Basalt Vault verifier helper.

Given a maze fixture, a target maze id, and a port, this:
  1. launches a fresh vault_server.py on that fixture,
  2. runs the deliverable /app/grid.py against it (pointing at that port),
  3. checks the live game reached the max score / finished at the exit,
  4. parses the produced map.txt and validates:
       - the map grid is byte-identical to the true maze grid,
       - every winning move is a legal zero-indexed adjacent move from start,
       - the traversal covers every passable cell exactly (full exploration)
         and ends on the exit.

Exit 0 on success, non-zero on failure. Diagnostics to stdout.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.request


def http_post(base, path, payload):
    req = urllib.request.Request(
        base + "/" + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", required=True)
    ap.add_argument("--maze", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--out", default="/app/map.txt")
    args = ap.parse_args()

    with open(args.fixture) as fh:
        data = json.load(fh)
    mazes = data if isinstance(data, list) else data.get("mazes", [])
    maze = next((m for m in mazes if m["id"] == args.maze), None)
    if maze is None:
        print("FAIL: maze id %s not in fixture" % args.maze)
        return 1

    srv = subprocess.Popen(
        ["python3", "-u", "/app/vault_server.py", "--port", str(args.port),
         "--fixture", args.fixture],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    base = "http://127.0.0.1:%d" % args.port
    try:
        up = False
        for _ in range(300):
            try:
                urllib.request.urlopen(base + "/ping", timeout=1)
                up = True
                break
            except Exception:
                time.sleep(0.1)
        if not up:
            print("FAIL: server never came up")
            return 1

        proc = subprocess.run(
            ["python3", "/app/grid.py", args.maze, "--port", str(args.port),
             "--out", args.out],
            capture_output=True, text=True, timeout=240,
        )
        if proc.returncode != 0:
            print("FAIL: grid.py rc=%d" % proc.returncode)
            print((proc.stderr or "")[-1200:])
            return 1

        st = http_post(base, "state", {"id": args.maze})
        if not (st.get("collected") and st.get("finished") and st.get("alive")
                and st.get("registered") and st.get("score") == 300):
            print("FAIL: game state incorrect: %s" % json.dumps(st))
            return 1

        try:
            text = open(args.out).read().splitlines()
        except OSError:
            print("FAIL: no map at %s" % args.out)
            return 1
        if not text or text[0] != "BASALT-VAULT-MAP":
            print("FAIL: bad map header")
            return 1
        header = {}
        i = 1
        while i < len(text) and "=" in text[i]:
            k, _, v = text[i].partition("=")
            header[k] = v
            i += 1
        if header.get("maze") != args.maze:
            print("FAIL: wrong maze in map: %r" % header)
            return 1
        rows = int(header["rows"])
        cols = int(header["cols"])
        if rows != maze["rows"] or cols != maze["cols"]:
            print("FAIL: dims %sx%s != fixture %sx%s"
                  % (rows, cols, maze["rows"], maze["cols"]))
            return 1
        grid_lines = text[i:i + rows]
        i += rows
        if i >= len(text) or text[i] != "MOVES":
            print("FAIL: MOVES marker not found")
            return 1
        moves = text[i + 1:]
        if moves and moves[-1] == "END":
            moves = moves[:-1]

        start = tuple(maze["start"])
        tres = tuple(maze["treasure"])
        exitc = tuple(maze["exit"])
        walls = {(x[0], x[1]) for x in maze["walls"]}
        for r in range(rows):
            cells = grid_lines[r].split()
            if len(cells) != cols:
                print("FAIL: grid row %d width %d != %d" % (r, len(cells), cols))
                return 1
            for c in range(cols):
                expect = ("E" if (r, c) == exitc else
                          "T" if (r, c) == tres else
                          "S" if (r, c) == start else
                          "#" if (r, c) in walls else ".")
                if cells[c] != expect:
                    print("FAIL: grid[%d][%d] %r != %r" % (r, c, cells[c], expect))
                    return 1

        if not moves:
            print("FAIL: no moves")
            return 1
        visited = set()
        prev_end = start
        for ln in moves:
            parts = ln.split("->")
            if len(parts) != 2:
                print("FAIL: malformed move line %r" % ln)
                return 1
            a = parts[0].split(",")
            b = parts[1].split(",")
            if len(a) != 2 or len(b) != 2:
                print("FAIL: malformed move line %r" % ln)
                return 1
            try:
                sr, sc = int(a[0]), int(a[1])
                dr, dc = int(b[0]), int(b[1])
            except ValueError:
                print("FAIL: non-integer move line %r" % ln)
                return 1
            if (sr, sc) != prev_end:
                print("FAIL: move chain broken at %r" % ln)
                return 1
            if abs(dr - sr) + abs(dc - sc) != 1:
                print("FAIL: non-adjacent move %r" % ln)
                return 1
            if not (0 <= dr < rows and 0 <= dc < cols) or (dr, dc) in walls:
                print("FAIL: move into wall/OOB %r" % ln)
                return 1
            visited.add((dr, dc))
            visited.add((sr, sc))
            prev_end = (dr, dc)
        if prev_end != exitc:
            print("FAIL: traversal does not end at exit")
            return 1
        expected = set()
        for r in range(rows):
            for c in range(cols):
                if (r, c) not in walls:
                    expected.add((r, c))
        if visited != expected:
            print("FAIL: coverage mismatch visited=%d passable=%d extra=%d "
                  "missing=%d"
                  % (len(visited), len(expected),
                     len(visited - expected), len(expected - visited)))
            return 1

        print("PASS: maze %s -> score 300, map valid, %d winning moves"
              % (args.maze, len(moves)))
        return 0
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=5)
        except Exception:
            try:
                srv.kill()
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())