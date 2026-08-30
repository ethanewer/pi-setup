#!/usr/bin/env bash
# Oracle for dune-beacon: author and then RUN the real work to produce every
# deliverable. Never reads /tests.
#
#   Part 1  maze solver: debug the exploration routine offline against the
#           reference fixture, then drive the live server on all instances.
#   Part 2  drive the text adventure over a PTY to its ending, capture the
#           exact ending line, and quit normally to flush the SQLite DB.
#   Part 3  canonical Vimscript that reproduces the captured layout.
#   Part 4  Vim macros under a total keystroke budget.
set -euo pipefail
cd /app

# ---------------------------------------------------------------------------
# Part 1 / solve.py (maze solver, --live and --sim, one shared explore routine)
# ---------------------------------------------------------------------------
cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Dune Beacon maze solver.

Drives the interactive maze (/app/server.py) with single and batched movement
commands, parses the returned moved/wall/exit responses, and reconstructs the
full layout.  Two modes share one exploration routine:

    python3 /app/solve.py --live <maze_file> <out_file>
        spawn /app/server.py <maze_file> on pipes and explore it interactively.
    python3 /app/solve.py --sim  <maze_file> <out_file>
        offline self-test from the layout file (answers probes locally), used
        to debug coverage against the reference fixture before trusting live.

Output: one line per grid row; '#' wall, ' ' interior, 'S' start, 'E' exit.
"""
import json
import os
import subprocess
import sys

DIRS = {"n": (-1, 0), "s": (1, 0), "e": (0, 1), "w": (0, -1)}
SERVER = "/app/server.py"


def explore(sess):
    h, w, start = parse_banner(sess.banner)
    grid = [["#"] * w for _ in range(h)]
    grid[start[0]][start[1]] = "S"
    visited = {start}
    walls = set()
    stack = [start]
    while stack:
        cell = stack[-1]
        nxt = None
        nb = None
        for d, (dr, dc) in DIRS.items():
            cand = (cell[0] + dr, cell[1] + dc)
            if 0 <= cand[0] < h and 0 <= cand[1] < w \
                    and cand not in visited and cand not in walls:
                nxt, nb = d, cand
                break
        if nxt is None:                       # this cell fully mapped: backtrack
            stack.pop()
            if stack:
                parent = stack[-1]
                dr = parent[0] - cell[0]
                dc = parent[1] - cell[1]
                back = [k for k, (a, b) in DIRS.items()
                        if (a, b) == (dr, dc)][0]
                sess.step([back])
            continue
        resp = sess.step([nxt])[0]
        if resp == "wall":
            walls.add(nb)
        else:
            visited.add(nb)
            grid[nb[0]][nb[1]] = "E" if resp == "exit" else " "
            stack.append(nb)
    return ["".join(row) for row in grid]


class ServerSession(object):
    def __init__(self, maze_file):
        self.proc = subprocess.Popen(
            [sys.executable, SERVER, maze_file],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.banner = self.proc.stdout.readline().strip()

    def step(self, moves):
        self.proc.stdin.write(json.dumps({"moves": moves}) + "\n")
        self.proc.stdin.flush()
        return json.loads(self.proc.stdout.readline())["responses"]

    def close(self):
        try:
            self.proc.stdin.write(json.dumps({"bye": True}) + "\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


class SimSession(object):
    """Offline mock that behaves exactly like the server, reading the layout
    from the file directly.  Used to verify the routine on a known fixture."""

    def __init__(self, maze_file):
        rows = [r.rstrip("\r\n") for r in open(maze_file) if r.strip()]
        self.grid = rows
        self.h = len(rows)
        self.w = len(rows[0])
        start = next((r, c) for r in range(self.h) for c in range(self.w)
                     if rows[r][c] == "S")
        self.pos = list(start)
        self.banner = "READY ROWS=%d COLS=%d START=%d,%d" % (
            self.h, self.w, start[0], start[1])

    def step(self, moves):
        resps = []
        for m in moves:
            if m not in DIRS:
                resps.append("wall")
                continue
            dr, dc = DIRS[m]
            nr, nc = self.pos[0] + dr, self.pos[1] + dc
            if not (0 <= nr < self.h and 0 <= nc < self.w) \
                    or self.grid[nr][nc] == "#":
                resps.append("wall")
            else:
                self.pos = [nr, nc]
                resps.append("exit" if self.grid[nr][nc] == "E" else "moved")
        return resps

    def close(self):
        pass


def parse_banner(banner):
    parts = banner.replace("READY", "").split()
    h = int(parts[0].split("=")[1])
    w = int(parts[1].split("=")[1])
    sr, sc = map(int, parts[2].split("=")[1].split(","))
    return h, w, (sr, sc)


def main():
    mode, maze_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
    sess = SimSession(maze_file) if mode == "--sim" else ServerSession(maze_file)
    try:
        grid = explore(sess)
    finally:
        sess.close()
    os.makedirs(os.path.dirname(os.path.abspath(out_file)), exist_ok=True)
    with open(out_file, "w") as fh:
        fh.write("\n".join(grid) + "\n")


if __name__ == "__main__":
    main()
PY
chmod +x /app/solve.py

# 1a) offline-self-test the routine against the reference fixture (C-991688)
python3 /app/solve.py --sim /app/data/reference.txt /tmp/ref_sim.out
if ! diff -q /tmp/ref_sim.out /app/data/reference.txt >/dev/null; then
    echo "oracle: offline reference coverage failed" >&2
    exit 1
fi

# 1b) drive the LIVE server on the three shipped instances -> /app/maps/*.out
mkdir -p /app/maps
for name in reef island channel; do
    python3 /app/solve.py --live /app/instances/$name.txt /app/maps/$name.out
    if ! diff -q /app/maps/$name.out /app/instances/$name.txt >/dev/null; then
        echo "oracle: live coverage failed on $name" >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Part 2 / text adventure over a PTY -> ending.txt + DB flush on normal quit
# ---------------------------------------------------------------------------
cat > /app/drive.py <<'PY'
import os, pty, re, select, sys, time

pid, fd = pty.fork()
if pid == 0:
    os.execvp("python3", ["python3", "/app/adventure.py"])

output = []
def drain(ms):
    end = time.time() + ms / 1000.0
    out = b""
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    return out.decode("utf-8", errors="replace")

def act(cmd):
    os.write(fd, (cmd + "\n").encode())
    # adaptive wait: drain until the game goes quiet (bounded), so slow
    # resource-constrained containers never lose a command to a fixed timer
    deadline = time.time() + 5.0
    quiet_since = None
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if chunk:
                output.append(chunk.decode("utf-8", errors="replace"))
                quiet_since = time.time()
                continue
        if quiet_since is not None and time.time() - quiet_since > 0.25:
            break

# deterministic walk: stables?key?gate?causeway?pier?boat?isle?tower?gallery?light
for cmd in ["s", "take key", "n", "n", "open gate",
            "e", "e", "take boat", "up", "up", "up", "light", "quit"]:
    act(cmd)
output.append(drain(400))

# capture the exact ending line from the transcript
full = "\n".join(output)
m = re.search(r"THE BEACON IS WOKEN; the storm breaks and the last gate is calmed\.", full)
if not m:
    sys.stderr.write("drive.py: ending message not found in transcript\n")
    sys.exit(1)
with open("/app/ending.txt", "w") as fh:
    fh.write(m.group(0).rstrip("\r") + "\n")

try:
    os.close(fd)
except OSError:
    pass
os.waitpid(pid, 0)

# deterministic flush check: poll the SQLite DB until the quit actually
# committed (bounded), so a slow container cannot race the verifier
import sqlite3
deadline = time.time() + 30
flushed = False
while time.time() < deadline:
    try:
        con = sqlite3.connect("/app/state/beacon.db")
        rows = con.execute("SELECT reached_ending FROM players").fetchall()
        ev = con.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        con.close()
        if rows and rows[0][0] == 1 and ev > 0:
            flushed = True
            break
    except sqlite3.Error:
        pass
    time.sleep(0.5)
if not flushed:
    sys.stderr.write("drive.py: DB flush not visible after quit\n")
    sys.exit(1)
print("ending captured, DB flushed by normal quit")
PY
python3 /app/drive.py
test -s /app/ending.txt

# ---------------------------------------------------------------------------
# Part 3 / layout.vim (canonical Vimscript recreating the captured layout)
# ---------------------------------------------------------------------------
cat > /app/layout.vim <<'VIM'
" Dune Beacon: reproduce the captured tab/window/buffer topology (2 tabs).
set splitright
set splitbelow
" tab 1: reuse the initial tab -> two vertically-split windows
edit deck.vim
vnew
edit cargo.txt
" tab 2: tall left window + a vertical split of two on its right
tabnew
edit sail.vim
vnew
edit rudder.vim
split
edit galley.txt
" return to tab 1
execute "tabnext 1"
VIM

# ---------------------------------------------------------------------------
# Part 4 / macros.vim under the keystroke budget (transform source->target)
# ---------------------------------------------------------------------------
cat > /app/macros.vim <<'VIM'
" Dune Beacon macros: q rewrites each '<word> <num>' line into
" '<word> -> <num>' in only a handful of keystrokes.  Total macro length is
" tiny, far under the 150-keystroke budget.
let @q = "0f s -> \e"
VIM

# Sanity: applying @q yields target_lines.txt
vim -Nu NONE -i NONE -n --not-a-term \
    -c "source /app/macros.vim" -c "edit /app/source_lines.txt" \
    -c "%global/^/normal @q" -c "write! /tmp/macro_check.txt" -c "qa!" >/dev/null 2>&1
diff -q /tmp/macro_check.txt /app/target_lines.txt >/dev/null \
    || { echo "oracle: macro transform mismatch" >&2; exit 1; }

# Every declared deliverable present
for f in /app/solve.py /app/maps/reef.out /app/maps/island.out \
         /app/maps/channel.out /app/ending.txt /app/layout.vim /app/macros.vim; do
    test -s "$f" || { echo "oracle: missing $f" >&2; exit 1; }
done
echo "oracle complete: all deliverables produced"
