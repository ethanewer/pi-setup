# Kiln Vane — swatch expander for the pattern loom

The **Kiln Vane textile works** stores its weave motifs as tiny 2x2 tiles. Before a motif
is sent to the loom it is expanded into a full 6x6 swatch by a fixed, deterministic
procedure. Your job is to implement that procedure as reusable, importable code and to use
it to produce the swatch for the motif currently on the loom. Everything is **Python 3.12,
standard library only**. Work in `/app`.

Leave the provided file `/app/tile.json` untouched.

## Deliverables (both required)

1. `/app/loom.py` — an importable module defining:

   ```python
   def weave(tile):
       ...
   ```

   `tile` is a `2x2` list-of-lists of integers. `weave` must return a `6x6`
   list-of-lists of integers computed **generally** for any `tile` according to the
   operating rule below — never special-cased to one input. The module must also be
   runnable as a CLI:

   ```
   python3 /app/loom.py <tile_json> <output_json>
   ```

   where `<tile_json>` holds `{"tile": [[a, b], [c, d]]}` and `<output_json>` receives the
   resulting 6x6 grid as a JSON list-of-lists.

2. `/app/swatch.json` — the 6x6 grid produced by running your program on the provided
   motif:

   ```
   python3 /app/loom.py /app/tile.json /app/swatch.json
   ```

## The operating rule

Given the 2x2 `tile`, build the 6x6 swatch in three ordered steps:

1. **Tile**: cover the 6x6 with 3x3 copies of `tile`, so the intermediate cell at
   `(r, c)` equals `tile[r % 2][c % 2]`.
2. **Horizontal shift**: shift every row `r` circularly **right** by `((r + 1) % 3)`
   columns — the element originally at column `c` lands at column
   `(c + ((r + 1) % 3)) % 6` (equivalently, the value at column `c` of the shifted row is
   taken from column `(c - ((r + 1) % 3)) % 6` of the tiled row).
3. **Vertical shift**: shift every column `c` circularly **up** by `((c + 2) % 3)` rows —
   the value at row `r` of the final grid is taken from row `(r + ((c + 2) % 3)) % 6` of
   the horizontally shifted grid.

Sanity check — `weave([[1, 2], [3, 4]])` must return exactly:

```
[1, 1, 3, 2, 2, 4]
[4, 4, 1, 3, 3, 2]
[1, 2, 4, 2, 1, 3]
[3, 3, 1, 4, 4, 2]
[2, 2, 3, 1, 1, 4]
[3, 4, 2, 4, 3, 1]
```

Note the sanity example above is only a check: the grader calls `weave()` on other 2x2
tiles — including tiles with repeated values — and compares the entire 6x6 output, so the
shift directions and offsets must be implemented exactly as stated, for arbitrary input.

## Constraints

- `weave` must be a pure function callable with new inputs; the verifier imports
  `/app/loom.py` and calls it directly on hidden tiles.
- Standard library only; no network access; do not install packages.
- Do not modify `/app/tile.json`.
