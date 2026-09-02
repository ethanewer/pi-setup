You are writing a small interpreter for **G-code**, the language used by CNC machines. The program in `/app/move.gcode` uses **absolute positioning**: after a `G90` command, coordinates in a move line are absolute positions.

Supported commands:
- Comments: a line whose first non-space character is `;` or `(` is a comment line and is ignored (also, text after a `;` on a move line is ignored).
- `G` commands: `G0`/`G1` set motion mode (mode does not affect position tracking).
- `G90` sets absolute mode (the default). Coordinates in `G0`/`G1` lines are absolute positions.

Each move line looks like `G0 X<val> Y<val>` or `G1 X<val> Y<val>` — one or both of X and Y
may be present; only specified axes change. The file begins with a `;` comment line and a
`G90` line, followed by move lines. Unrecognized lines are ignored.

The machine starts at position `(0, 0)`.

Write `/app/interpreter.py` that:
1. Reads `/app/move.gcode`.
2. Parses each line, updating the current absolute position.
3. Writes `/app/final_pos.json` containing exactly:
```json
{"x": <final x rounded to 3 decimals>, "y": <final y rounded to 3 decimals>}
```

Run your script so `/app/final_pos.json` has the correct final position. Use `python3` (the `re` module is standard).