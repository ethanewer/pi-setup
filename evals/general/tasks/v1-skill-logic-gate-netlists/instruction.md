# Logic-gate netlists

A combinational **netlist** connects logic gates. Evaluate all wire values for the following netlist.

Primary inputs: `A = 1`, `B = 0`.

Gates and their outputs:
- `C = A AND B`       → 1 AND 0 = **0**
- `D = A OR B`        → 1 OR 0  = **1**
- `E = NOT C`         → NOT 0   = **1**
- `F = C XOR D`       → 0 XOR 1 = **1**

Write all five wire values to `/app/wires.json`:

```json
{
  "A": 1,
  "B": 0,
  "C": 0,
  "D": 1,
  "E": 1,
  "F": 1
}
```

Use `0`/`1` integer bit values as shown.