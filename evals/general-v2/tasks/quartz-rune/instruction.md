# Quartz Rune — compile integer arithmetic into a finite gate network

The numerics team needs the scalar kernel

```
y = F(isqrt(x)) mod 2^32
```

rebuilt as a **finite operator network** (a combinational circuit graph), not
as ordinary code. For every unsigned 32-bit input `x` (`0 <= x <= 4294967295`):

- `s = isqrt(x)` — the largest integer `s` with `s*s <= x`;
- `y = F_s mod 2^32` — the `s`-th Fibonacci number reduced modulo `2^32`,
  with `F_0 = 0`, `F_1 = 1`, `F_n = F_(n-1) + F_(n-2)`.

You are in `/app` (Debian, Python 3.12). Do **not** modify `/app/probe_inputs.txt`.

## Deliverables (all three required)

1. `/app/circuit.gn` — the operator network (format below).
2. `/app/verify_circuit.py` — a self-checking validator (contract below).
3. `/app/circuit_report.json` — the network's outputs on the supplied probe
   inputs `/app/probe_inputs.txt` (schema below).

## Network format (`/app/circuit.gn`)

The file starts with four header lines, then node definition lines. `#`
comment lines and blank lines are ignored anywhere.

```
VERSION quartz-rune/gate-v2
WIDTH 32
LIMIT 520
RESULT <node_id>
# comment
<id> = IN
<id> = CONST <uint32>
<id> = SUM <a> <b>
<id> = DIF <a> <b>
<id> = PRD <a> <b>
<id> = LSH <a> <k>
<id> = RSH <a> <k>
<id> = BAND <a> <b>
<id> = BOR  <a> <b>
<id> = BXOR <a> <b>
<id> = FLIP <a>
<id> = PICK <c> <a> <b>
<id> = LESS <a> <b>
```

Semantics — every node value is an unsigned 32-bit integer:

- `IN`: the 32-bit input `x`. Exactly one `IN` node must exist.
- `CONST <v>`: literal, `0 <= v <= 4294967295`.
- `SUM`, `DIF`, `PRD`: `(a+b) mod 2^32`, `(a-b) mod 2^32`, `(a*b) mod 2^32`.
- `LSH <a> <k>` / `RSH <a> <k>`: shift by a constant `0 <= k <= 31`; `LSH`
  keeps the low 32 bits.
- `BAND`, `BOR`, `BXOR`: bitwise; `FLIP`: 32-bit complement.
- `PICK <c> <a> <b>`: selects `a` when `c != 0`, else `b`.
- `LESS <a> <b>`: `1` when unsigned `a < b`, else `0`.

Structural rules the grader enforces:

- Node ids are non-negative integers, **strictly increasing** down the file,
  starting at `0`, contiguous (`0,1,2,...`). Every operand `a`, `b`, `c` must
  reference a **strictly earlier** node id (the graph is topologically ordered
  — no loops, no memory, no jumps).
- Header lines precede all node lines; `RESULT <id>` names the node whose
  value is the function output `y` (it must be a defined node).
- The number of `id = ...` lines must not exceed the declared `LIMIT` (520).
  This is a hard ceiling: a giant lookup table will not fit. Keep the
  arithmetic compact — one `CONST` node can be reused by many references.

## `/app/verify_circuit.py`

```
python3 /app/verify_circuit.py <inputs_file>
```

- Loads `/app/circuit.gn`, evaluates the network for every input listed in
  `<inputs_file>`, and compares against the exact reference computed with
  Python's `math.isqrt` plus a fast-doubling Fibonacci mod `2^32`.
- `<inputs_file>` has one unsigned 32-bit integer per line (decimal or `0x...`
  hex); blank lines and `#` comments are ignored.
- If **every** value matches, print a line containing `PASS` and exit `0`;
  otherwise print `FAIL` and exit non-zero.

The grader runs this validator on hidden input files **and** independently
re-evaluates `/app/circuit.gn` with its own interpreter over the same inputs,
so the network itself must be correct — the validator must not paper over a
wrong circuit.

## `/app/circuit_report.json`

JSON object, exactly these keys:

```json
{
  "task": "quartz-rune",
  "nodes": <int, number of node lines in circuit.gn>,
  "result_node": <int, the RESULT node id>,
  "outputs": { "<decimal input>": <int y>, ... }
}
```

`outputs` has one entry per distinct input in `/app/probe_inputs.txt`, keyed
by the input's **decimal** value, with the network's output for that input.

## Edge cases the grader probes

Hidden input files stay inside the documented domain `0 <= x <= 2^32-1` and
include: `x = 0` (→ `y = 0`), tiny values, perfect squares and their
neighbours on both sides (e.g. `65535^2 - 1`, `65535^2`, `65535^2 + 1`),
hex-formatted inputs, duplicate values, and large values such as `2^32-1`
(isqrt `65535`, so `y = F_65535 mod 2^32`).

Hints: `isqrt` fits in 16 fixed restoring iterations using `LESS` + `PICK`
(guard the subtract — `DIF` wraps); Fibonacci for an input-dependent index is
affordable with **fast doubling**,
`F_(2n) = F_n*(2F_(n+1) - F_n)`, `F_(2n+1) = F_n^2 + F_(n+1)^2` (all mod
`2^32`), walking the bits of `s` from bit 31 down and choosing the
continuation with `PICK`. Everything fits well inside 520 nodes.

## Constraints

- The grader runs your program and network **unchanged** on hidden inputs, so
  do not hard-code the probe file's contents.
- Standard library only; no network access.
