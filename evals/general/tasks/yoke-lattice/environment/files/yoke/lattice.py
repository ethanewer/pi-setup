"""yoke.lattice — a small but real grid model.

A Grid is a rectangular fixed-width tile lattice.  Each cell holds a single
ASCII tile code ('.' means empty).  A *yoke* is a row that is fully covered by
exactly one non-empty code.  The class supports parsing the plain-text format,
rendering, transposition and a lattice product (join) used by the tests.
"""


class GridError(ValueError):
    """Raised when grid text is not a rectangular fixed-width lattice."""


class Grid:
    """A rectangular lattice of single-character tile codes."""

    def __init__(self, rows):
        if not rows:
            raise GridError("grid must have at least one row")
        width = len(rows[0])
        for i, row in enumerate(rows):
            if len(row) != width:
                raise GridError(
                    "row %d has width %d, expected %d" % (i, len(row), width))
        for i, row in enumerate(rows, 1):
            for j, cell in enumerate(row, 1):
                if not (cell == "." or (cell.isascii() and cell.isalnum())):
                    raise GridError(
                        "cell at row %d column %d is not a tile code: %r"
                        % (i, j, cell))
        self.rows = [row if isinstance(row, str) else "".join(row)
                     for row in rows]

    # -- construction ----------------------------------------------------
    @classmethod
    def parse(cls, text):
        """Build a Grid from plain text (one row per line, no blank lines)."""
        lines = text.splitlines()
        lines = [ln.rstrip("\r") for ln in lines if ln.strip() != ""]
        if not lines:
            raise GridError("empty grid text")
        return cls(lines)

    @classmethod
    def empty(cls, height, width):
        return cls(["." * width for _ in range(height)])

    # -- properties ------------------------------------------------------
    @property
    def height(self):
        return len(self.rows)

    @property
    def width(self):
        return len(self.rows[0])

    def cell(self, row, col):
        """The tile code at 0-based (row, col); '.' for empty."""
        return self.rows[row][col]

    def yokes(self):
        """(row, code) pairs for rows with no empty cells and a single code."""
        out = []
        for i, row in enumerate(self.rows):
            if "." in row:
                continue
            codes = {c for c in row}
            if len(codes) == 1:
                out.append((i, codes.pop()))
        return out

    # -- transforms ------------------------------------------------------
    def transpose(self):
        return Grid(["".join(col) for col in zip(*self.rows)])

    def flipped(self):
        return Grid(["".join(reversed(row)) for row in self.rows])

    def join(self, other, code):
        """Lattice product: place `other` inside every non-empty cell of self.

        Returns a Grid with height = height * other.height and
        width = width * other.width.  Empty cells expand to empty blocks.
        """
        if not isinstance(other, Grid):
            raise TypeError("join() needs another Grid")
        out = []
        for row in self.rows:
            blocks = []
            for cell in row:
                if cell == ".":
                    blocks.append(Grid.empty(other.height, other.width))
                else:
                    blocks.append(other)
            for subrow in range(other.height):
                out.append("".join(b.rows[subrow] for b in blocks))
        return Grid(out)

    # -- rendering -------------------------------------------------------
    def render(self):
        """Aligned rendering with the row number in the left gutter."""
        gutter = len(str(self.height))
        lines = []
        for i, row in enumerate(self.rows):
            lines.append("%*d|%s" % (gutter, i, "".join(row)))
        return "\n".join(lines)

    def __repr__(self):  # pragma: no cover
        return "Grid(%dx%d)" % (self.height, self.width)

    def __eq__(self, other):
        return isinstance(other, Grid) and self.rows == other.rows