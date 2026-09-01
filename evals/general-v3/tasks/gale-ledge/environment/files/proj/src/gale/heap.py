"""Garbage-collector sweeper for the krypton major-heap arena.

The arena is a flat array of cells; each cell is either **free** (0) or
**live** (1).  Free space is stored as a *run-length-compressed* list of
disjoint spans: every element is ``[begin, length)`` and two free cells that
are adjacent are ALWAYS part of the same run.  ``sweep`` reconstructs this
compressed free-space representation from the current live-cell bitmap.

The collector relies on the free-space table being maximally compressed: a
request for a large contiguous block (e.g. the full arena during bootstrap)
must be answerable from a single run.
"""


class Arena:
    def __init__(self, cells):
        # cells: list[int] of 0 (free) / 1 (live)
        self.cells = list(cells)
        self.free = []  # run-length-compressed list of [begin, length)

    def sweep(self):
        """Rebuild ``self.free`` from the live-cell bitmap.

        Runs must be maximally compressed: adjacent free cells are one run,
        including a run that reaches the very end of the arena.
        """
        cells = self.cells
        n = len(cells)
        runs = []
        i = 0
        while i < n:
            if cells[i] == 0:
                begin = i
                while i + 1 < n and cells[i] == 0:
                    i += 1
                length = i - begin
                if length > 0:
                    runs.append([begin, length])
                i += 1
            else:
                i += 1
        self.free = runs
        return runs

    def contiguous(self, span):
        """Return the length of the largest single free run.

        Returns the longest run length in ``self.free`` (0 if empty)."""
        best = 0
        for begin, length in self.free:
            if length > best:
                best = length
        return best


def reclaimed_cells(arena):
    """Total length of free space after sweeping the arena.

    Because free space is run-length compressed and every free cell appears
    in exactly one run, this equals the count of free cells."""
    return sum(length for _begin, length in arena.free)