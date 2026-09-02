# Glass Quill — Vexil Kestrel-F co-processor tape-out

You are on the tape-out team at **Vexil Semiconductor**. The next spin of the
Kestrel-F co-processor needs one new combinational hard-macro: the `QFIB`
block. Given an unsigned 32-bit input word `x`, the block computes

```
s = isqrt(x)            # largest integer s with s*s <= x
y = F_s mod 2^32        # F_0 = 0, F_1 = 1, F_n = F_(n-1) + F_(n-2)
```

and drives `y` on its 32-bit output bus. Synthesis is **your** job: you must
hand-author the logic as a finite operator network in the company netlist
format `NLV2`. There are no loops, no branches, no state and no memory — the
network is a straight-line DAG evaluated once per input.

Working directory: `/app`. Python 3.12 is available. Do not modify
`/app/probe_inputs.txt`.

## Deliverables (all three required)

1. `/app/netlist.txt` — the QFIB logic in `NLV2` format (spec below). It must
   be correct for **every** unsigned 32-bit input, not just the probe file.
2. `/app/eval_net.py` — a self-checking evaluator (interface below).
3. `/app/build_report.json` — a build report about your own netlist (schema
   below), filled from the actual file you shipped.

## The `NLV2` netlist format

A netlist file has this exact structure:

```
NETLIST NLV2
WIDTH 32
BUDGET 768
DRIVE <node_id>
# a comment line (any line whose first non-space char is '#') is ignored
<id> := IN
<id> := K <uint32>
<id> := ADD <a> <b>
<id> := SUB <a> <b>
<id> := MUL <a> <b>
<id> := SHL <a> <k>
<id> := SHR <a> <k>
<id> := AND <a> <b>
<id> := OR  <a> <b>
<id> := XOR <a> <b>
<id> := NOT <a>
<id> := CMP <a> <b>
<id> := SEL <c> <a> <b>
```

Semantics — every node holds one unsigned 32-bit value:

- `IN` — copies the 32-bit input word `x`. **Exactly one** `IN` node exists.
- `K <v>` — literal constant, `0 <= v <= 4294967295`.
- `ADD`/`SUB`/`MUL` — `(a+b) mod 2^32`, `(a-b) mod 2^32`, `(a*b) mod 2^32`.
- `SHL <a> <k>` — `(a << k)` keeping the low 32 bits; `SHR <a> <k>` — logical
  right shift. The shift amount `k` is a literal `0 <= k <= 31`.
- `AND`/`OR`/`XOR`/`NOT` — bitwise; `NOT` is the full 32-bit complement.
- `CMP <a> <b>` — `1` when unsigned `a < b`, else `0`.
- `SEL <c> <a> <b>` — `a` when `c != 0`, else `b`.

Hard rules the tape-out checker enforces:

- Node ids are non-negative integers, **strictly increasing** down the file,
  starting at `0`. Every operand refers to a **strictly earlier** node id.
- Header lines (`NETLIST`, `WIDTH`, `BUDGET`, `DRIVE`) precede all node lines.
- `DRIVE` names the node whose value is the function result `y`.
- The number of `<id> :=` node lines must **not exceed** the declared
  `BUDGET`. You may declare `BUDGET 768` and use fewer. This ceiling makes a
  brute lookup-table network impossible — the arithmetic has to be compact.
- Blank lines and `#` comments are allowed anywhere.

## `/app/eval_net.py` — evaluator contract

```
python3 /app/eval_net.py <inputs_file> [netlist_path]
```

- `<netlist_path>` defaults to `/app/netlist.txt`.
- `<inputs_file>`: one unsigned 32-bit integer per line (decimal or `0x...`
  hex); blank lines and `#` comments are ignored.
- For each input the evaluator compares the netlist output against an
  **independent** reference computed in plain Python (`math.isqrt` plus a
  fast-doubling Fibonacci mod `2^32`).
- If every value matches: print a line containing `PASS` and exit `0`.
  Otherwise print `FAIL` and exit non-zero.
- The evaluator must actually interpret `/app/netlist.txt` — it may not fake a
  pass by computing the reference alone. The grader runs it on hidden input
  files **and** re-evaluates `/app/netlist.txt` with its own independent
  interpreter, so the shipped netlist itself must be right.

## `/app/build_report.json` — build report schema

```json
{
  "format": "NLV2",
  "width": 32,
  "budget": 768,
  "nodes_used": 470,
  "op_counts": {"IN": 1, "K": 9, "ADD": 34, "...": 0},
  "probe": [
    {"x": "0", "s": 0, "y": 0},
    {"x": "65536", "s": 256, "y": 2723753019}
  ]
}
```

- `nodes_used` = number of node lines actually present in `/app/netlist.txt`.
- `op_counts` = per-operator count over those node lines (include every
  operator that appears; omit zero-count operators or set them to 0 — both
  accepted, but a wrong non-zero count fails).
- `probe` = one entry **in file order** for every input in
  `/app/probe_inputs.txt`: `x` is the input as a decimal string (an int is
  also accepted), `s` = `isqrt(x)`, `y` = the QFIB result `F_s mod 2^32`.
- The verifier recomputes all of these from the shipped netlist and the probe
  file; hand-faked numbers that disagree with the real netlist fail.

## Edge cases the hidden tape-out vectors probe

- `x = 0` (`s = 0`, `F_0 = 0`), `x = 1`, and tiny squares vs non-squares.
- Exact squares and their neighbours (`s*s`, `s*s+1`, `(s+1)^2 - 1`).
- The top of the domain: `x = 2^32-1` gives `s = 65535`.
- Indices where `F_s` itself wraps mod `2^32` (e.g. `s = 48`, `s = 65535`).

## Constraints

- The verifier runs `/app/eval_net.py` unchanged and interprets
  `/app/netlist.txt` itself on hidden input files drawn from the documented
  domain `0 <= x <= 2^32-1`. Do not hard-code to the probe file.
- Standard library only; no network at verify time.
