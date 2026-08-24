# Decode the hidden message from a 3D-printer toolpath

In `/app` there is a large G-code file `job.gcode` (roughly 800 lines) for a
fused-filament 3D printer. It is a single-part job that prints an ornamental
nameplate. Most lines are **metadata** (slicer comments, bed-temperature
commands, `M140`/`M104`/`M553` heater feedback, `G28` homing) or **rapid
travel** (fast `G0` nozzle moves that do not extrude plastic). A few are
**drafting contours** (`G1` lines whose feed token is `F...`).

Only a small set of lines are **genuine printed segments**: `G1` motion lines
that also carry a part-extrusion feed token `E<number>` (e.g.
`G1 X128.48 Y-2.01 E12.5`). These are the only toolpath steps that actually lay
material, and they encode a hidden message, one letter each, in the order they
appear in the file.

## Decoding rule

For each genuine printed segment line that you find (a `G1` line containing a
part-extrusion `E<number>` token, ignoring all other line kinds):

1. Take the **integer part** (floor) of the `E` value. It is a 0-based index
   into the alphabet `A=0, B=1, ..., Z=25`.
2. Add the corresponding uppercase letter.
3. Concatenate those letters **in file order** (first printed segment to last).

The resulting 8-letter sequence is exactly one English word.

## Deliverable

Write exactly that decoded word to `/app/decoded.txt` (uppercase, no trailing
whitespace, no newline). For example, if the decoded word were `RELIC`, the file
content would be exactly `RELIC`.

Good luck. There is exactly one correct answer.