# Redcode (Core War assembly)

`/app/warrior.rc` contains a short **Redcode** program, one instruction per line, with
`;` denoting a comment line:

```
; demo
MOV 0, 1
ADD -1, 2
SPL 0, 7
JMZ -3, 0
DAT 0, 0
```

In this dialect, each instrinction line is `OPCODE A, B` where the opcode is one of the
Redcode op-codes and `A`, `B` are its two integer operand fields.

Write `/app/parse.py` that reads every **non-comment, non-empty** line and emits one
entry per line. Tokenize by splitting on whitespace and commas. The tokens are:

- `op` — the opcode (uppercase as written),
- `a` — first operand token (may be negative),
- `b` — second operand token (may be negative).

It also classifies each opcode into exactly one category:

- `data`  → MOV, DAT, DATX
- `arith` → ADD, SUB, MUL, DIV, MOD, SLT
- `split` → SPL
- `jump`  → JMP, JMZ, JMN, DJN

If a line has no second operand, set `b` to `null`. Emit the list as `/app/result.json`:

```json
[
  {"op": "MOV", "class": "data", "a": "0", "b": "1"},
  {"op": "ADD", "class": "arith", "a": "-1", "b": "2"},
  {"op": "SPL", "class": "split", "a": "0", "b": "7"},
  {"op": "JMZ", "class": "jump", "a": "-3", "b": "0"},
  {"op": "DAT", "class": "data", "a": "0", "b": "0"}
]
```

Run `python3 /app/parse.py` so the file is produced. The verifier recomputes the same
thing from `warrior.rc`; no hardcoding.