# Prism Pier maze session core. Provided, do not modify.
class MazeSession:
    def __init__(self, rows):
        # rows: list of equal-length strings of cell markers
        self._rows = [list(r) for r in rows]
        self._finalized = False

    def grid(self):
        return ["".join(row) for row in self._rows]

    def flag_visited(self, cells):
        # Mark trailing visit residues as 'X' (overwriting current marker).
        rows, cols = len(self._rows), len(self._rows[0])
        for (r, c) in cells:
            if 0 <= r < rows and 0 <= c < cols:
                self._rows[r][c] = "X"

    def finalize(self):
        # Resolve every visit residue back to open floor.
        for row in self._rows:
            for i in range(len(row)):
                if row[i] == "X":
                    row[i] = "."
        self._finalized = True

    def is_finalized(self):
        return self._finalized

    def write_map(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(self.grid()) + "\n")