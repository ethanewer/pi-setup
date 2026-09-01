# 3D-printer toolpath analysis

`/app/moves.gcode` holds a small G-code program describing a 3D-printer print toolpath.

In 3D-printer G-code:

- `G0` commands are **rapid travel / positioning** moves. The nozzle moves but extrudes no filament, so these moves do **not** add to the printed toolpath length.
- `G1` commands are **extrude (deposition)** moves. The nozzle deposits filament while moving, so these moves **do** add to the printed toolpath length.

Commands use absolute coordinates (mode `G90`), and every move is a straight segment from the previous recorded position to the new `X Y` coordinate stated on that line. Only the `X` and `Y` values matter; ignore `Z` and any trailing `E`/comment text.

## Task

Read `/app/moves.gcode` and compute the **total extruded (printed) toolpath length**: the sum of the Euclidean segment lengths of all `G1` moves only (ignore `G0` moves entirely — do not add their segment lengths to the total).

Write the result as an integer to `/app/answer.json`:

```json
{"total_extruded_length": 75}
```

where `75` is replaced by your computed value.

Constraints:
- All `G1` moves in the file travel purely along `X` or purely along `Y`, so every segment length is an exact integer; report the total as an exact integer with no decimals.
- Ignore `G90`/`G21`/comment lines.