"""UmberRidge CellGrid API.

A minimal in-memory spreadsheet grid. Values are placed into individual cells
via the public API method `set_cell(address, value)`. Every successful write is
logged; `export(path)` persists the whole transcript as JSON Lines, which
reconsider/export consumers later replay to reconstruct the populated grid.

Contract
--------
* address is a string of the form ``<COL><ROW>`` where COL is one or more ASCII
  uppercase letters (column index, 1-based per letter) and ROW is a positive
  integer (1-based row). Examples: "A1", "B4", "C7".
* Only scalar values (str / int / float) may be written. The address must be
  well-formed or `set_cell` raises `ValueError`.
"""
import json


class CellGrid:
    def __init__(self):
        # transcript of set_cell calls in call order
        self._ops = []

    def set_cell(self, address, value):
        if not isinstance(address, str) or not address:
            raise ValueError("bad cell address: %r" % (address,))
        col = "".join(ch for ch in address if ch.isalpha())
        row = "".join(ch for ch in address if ch.isdigit())
        if not col.isalpha() or not row or int(row) < 1:
            raise ValueError("bad cell address: %r" % (address,))
        if not isinstance(value, (str, int, float)):
            raise TypeError("cell value must be scalar, got %r" % (value,))
        self._ops.append({"cell": address, "value": value})

    def export(self, path):
        with open(path, "w") as fh:
            for op in self._ops:
                fh.write(json.dumps(op) + "\n")