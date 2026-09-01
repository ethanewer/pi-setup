"""
reference_maze.py -- a KNOWN maze fixture used to validate the exploration
routine OFFLINE before it is trusted on live (unknown) instances.

This is a small 5x5 winding maze with one extra loop. Every one of the 25 cells
is reachable from the start (0,0). Use it to prove your q/f CSS-free flood-fill
covers the whole grid before running against unknown mazes.

OPEN[(r,c)] = set of directions ('N','S','E','W') that are open passages.
"""
DIMS = (5, 5)          # rows, cols
START = (0, 0)         # (row, col) agent begins there

OPEN = {
    (0, 0): {'E'},          (0, 1): {'W', 'E'},   (0, 2): {'W', 'E'},
    (0, 3): {'W', 'E'},     (0, 4): {'W', 'S'},
    (1, 0): {'E'},          (1, 1): {'W', 'E'},   (1, 2): {'W', 'E', 'N'},
    (1, 3): {'W', 'E'},     (1, 4): {'W', 'S'},
    (2, 0): {'E'},          (2, 1): {'W', 'E'},   (2, 2): {'W', 'E'},
    (2, 3): {'W', 'E'},     (2, 4): {'W', 'S'},
    (3, 0): {'E'},          (3, 1): {'W', 'E'},   (3, 2): {'W', 'E'},
    (3, 3): {'W', 'E'},     (3, 4): {'W', 'S'},
    (4, 0): {'E'},          (4, 1): {'W', 'E'},   (4, 2): {'W', 'E'},
    (4, 3): {'W', 'E'},     (4, 4): {'W', 'N'},
}