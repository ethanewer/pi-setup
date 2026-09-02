"""
mazeapi.py  --  maze game server interface (games-and-maze bench).

The maze is UNKNOWN: you never learn its layout up front. You only get a
small window of feedback from wherever the pawn currently stands, and you must
travel through the maze -- physically moving one cell at a time -- to discover
every reachable cell and every wall boundary, then walk out to the exit.

Every maze instance is addressed by a *maze id* (a plain string). The maze
derives from that id deterministically; different ids produce different mazes
of different sizes. Nothing about the layout is exposed directly.

Workflow (see Maze below):
    maze = mazeapi.Maze("some-id")     # or mazeapi.start("some-id")
    rows, cols = maze.dimensions()
    sr, sc   = maze.start              # pawn's initial cell
    while ...:
        for d in ('N','S','E','W'):    # peek in every direction
            if maze.peek(d):           # passage is open this way
                moved = maze.move(d)   # step one cell (False if blocked)
        if maze.at_exit(): ...         # you found the exit

Squares are addressed as (row, col), 0-indexed top-left, with
N = row-1, S = row+1, E = col+1, W = col-1.

The exploration is navigation-constrained: you may only 'peek' the cell you are
currently standing on, and you may only 'move' through an open passage. This is
why a full systematic traversal (depth-first with backtracking through cycles
and dead ends) is required rather than a single pass over coordinates.
"""
import hashlib
import random

DIRS = ('N', 'S', 'E', 'W')
DELTA = {'N': (-1, 0), 'S': (1, 0), 'E': (0, 1), 'W': (0, -1)}
OPPOSITE = {'N': 'S', 'S': 'N', 'E': 'W', 'W': 'E'}


def _seed(maze_id):
    h = hashlib.sha256(str(maze_id).encode('utf-8')).hexdigest()
    return int(h[:12], 16)


def generate(seed):
    rng = random.Random(seed)
    rows = rng.randint(6, 9)
    cols = rng.randint(6, 9)
    walls = {}
    for r in range(rows):
        for c in range(cols):
            # open flag: True => passage open, False => wall (closed)
            walls[(r, c)] = {d: False for d in DIRS}
    # Carve a spanning tree with recursive backtracker.
    start = (0, 0)
    stack = [start]
    visited = {start}
    while stack:
        r, c = stack[-1]
        nbs = []
        for d in DIRS:
            dr, dc = DELTA[d]
            nr, nc = r + dr, c + dc
            if 0 <= nr < rows and 0 <= nc < cols and (nr, nc) not in visited:
                nbs.append(d)
        if not nbs:
            stack.pop()
            continue
        d = rng.choice(nbs)
        dr, dc = DELTA[d]
        nr, nc = r + dr, c + dc
        walls[(r, c)][d] = True
        walls[(nr, nc)][OPPOSITE[d]] = True
        visited.add((nr, nc))
        stack.append((nr, nc))
    # Add a few extra passages to create cycles / loops.
    for _ in range(rng.randint(1, 3)):
        r = rng.randrange(rows)
        c = rng.randrange(cols)
        d = rng.choice(DIRS)
        dr, dc = DELTA[d]
        nr, nc = r + dr, c + dc
        if 0 <= nr < rows and 0 <= nc < cols:
            walls[(r, c)][d] = True
            walls[(nr, nc)][OPPOSITE[d]] = True
    # The exit is the cell farthest (by BFS distance) from the start cell.
    exit_pos = _farthest(rows, cols, walls, start)
    return rows, cols, walls, start, exit_pos


def _farthest(rows, cols, walls, start):
    from collections import deque
    dist = {start: 0}
    q = deque([start])
    while q:
        r, c = q.popleft()
        for d in DIRS:
            if not walls[(r, c)][d]:
                continue
            dr, dc = DELTA[d]
            nr, nc = r + dr, c + dc
            if (nr, nc) not in dist:
                dist[(nr, nc)] = dist[(r, c)] + 1
                q.append((nr, nc))
    best = max(dist.items(), key=lambda kv: (kv[1], -kv[0][0], -kv[0][1]))
    return best[0]


def start(maze_id):
    """Return a fresh Maze instance bound to maze_id."""
    return Maze(maze_id)


class Maze(object):
    def __init__(self, maze_id):
        self.maze_id = str(maze_id)
        self.rows, self.cols, self._open, self.start, self.exit = generate(
            _seed(self.maze_id))
        self._r, self._c = self.start
        self._moves = 0
        self._budget = 80 + self.rows * self.cols * 6

    def dimensions(self):
        return (self.rows, self.cols)

    def position(self):
        return (self._r, self._c)

    def peek(self, d):
        if d not in DIRS:
            raise ValueError('bad direction: %r' % (d,))
        return self._open[(self._r, self._c)][d]

    def move(self, d):
        if d not in DIRS:
            raise ValueError('bad direction: %r' % (d,))
        self._moves += 1
        if self._moves > self._budget:
            raise RuntimeError('maze move budget exceeded')
        if not self._open[(self._r, self._c)][d]:
            return False
        dr, dc = DELTA[d]
        self._r += dr
        self._c += dc
        return True

    def at_exit(self):
        return (self._r, self._c) == self.exit

    def budget(self):
        return self._budget - self._moves

    # --- ground-truth accessors used ONLY by graders --------------------
    @property
    def _ground_open(self):
        return dict(self._open)

    @property
    def _ground_exit(self):
        return tuple(self.exit)