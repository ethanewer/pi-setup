# Wren-Vane — compile an integer datapath into a VECNET operator network

Wren Instruments is taping out a small datapath accelerator. The function the
silicon must evaluate, for every unsigned 32-bit input `x`
(`0 <= x <= 2^32-1`), is:

```
s = isqrt(x)         # the largest integer s with s*s <= x
y = F_s mod 2^32     # F_0 = 0, F_1 = 1, F_n = F_(n-1) + F_(n-2)
```

You must express `y` as a **finite operator network**: a straight-line sequence
of node definitions, each node computing one 32-bit operation from constants,
the input, or strictly earlier nodes. This is a combinational circuit graph —
there are **no loops, no jumps, no memory, no recursion**. Hidden test vectors
only ever use inputs in the documented domain `0 <= x <= 2^32-1`.

## Deliverables (all three required)

1. **`/app/vecnet.txt`** — the operator network (format below).
2. **`/app/vecsim.py`** — a runnable evaluator for the network format:
   ```
   python3 /app/vecsim.py <netlist_file> <vector_file> <output_json>
   ```
   It must parse ANY netlist conforming to the format below (not just your
   own), evaluate it for every input line in the vector file, and write the
   results to `output_json` as a JSON array of unsigned 32-bit integers, in
   the same order as the input lines.
3. **`/app/probe_out.json`** — the JSON array your simulator produces for the
   shipped probe vectors:
   ```
   python3 /app/vecsim.py /app/vecnet.txt /app/probe_in.txt /app/probe_out.json
   ```

Do **not** modify `/app/probe_in.txt`.

## VECNET1 file format (exact)

`/app/vecnet.txt` is a text file. Lines starting with `#` and blank lines are
ignored anywhere. The header lines come first, in this order:

```
FORMAT VECNET1
WIDTH 32
NODES <n>          # n = the exact number of node definition lines
OUTPUT <id>        # id of the output node
```

Then `<n>` node definition lines, one per node, with node ids `0 .. n-1`
appearing in increasing order. Each line is one of:

```
<id> = IN
<id> = K <u>              # constant, 0 <= u <= 2^32-1
<id> = ADD <a> <b>        # (a + b) mod 2^32
<id> = SUB <a> <b>        # (a - b) mod 2^32
<id> = MUL <a> <b>        # (a * b) mod 2^32
<id> = SLL <a> <k>        # (a << k) mod 2^32, k an integer 0..31
<id> = SRL <a> <k>        # (a >> k) logical, k an integer 0..31
<id> = AND <a> <b>        # bitwise and
<id> = OR  <a> <b>        # bitwise or
<id> = XOR <a> <b>        # bitwise xor
<id> = NOT <a>            # bitwise complement (mod 2^32)
<id> = SEL <c> <x> <y>    # c != 0 -> x, else y
<id> = LTU <a> <b>        # 1 if a < b unsigned, else 0
```

Rules the grader enforces:

- Exactly one node is `IN` (the 32-bit input). Every other node's operands are
  node ids **strictly smaller** than its own id.
- `NODES` must be at most **1200** and must equal the number of node lines.
- The `OUTPUT` node is the network's 32-bit result for the input.

## Correctness contract

For every 32-bit input `x`, evaluating the network with the `IN` node set to
`x` must yield `OUTPUT = F(isqrt(x)) mod 2^32`. The grader evaluates your
network with **its own independent evaluator** (not just your `vecsim.py`) on
edge cases (including `x = 0`, `x = 1`, perfect squares, `x = 2^32-1`, large
and small values) and on hidden random vectors, and additionally runs your
`/app/vecsim.py` on the same vectors — both must agree with the reference
exactly. Any input `0 <= x <= 2^32-1` may appear; recall `isqrt(2^32-1) =
65535`, and your network must be correct for all of it.

## Input file format for the simulator

`vector_file` is plain text: one unsigned 32-bit value per line (decimal or
`0x`-prefixed hex), blank lines ignored. Example `/app/probe_in.txt` is
shipped in exactly this format.

## What the grader does

- Checks the deliverables exist and `/app/probe_in.txt` is unmodified.
- Parses `/app/vecnet.txt` with its own VECNET1 evaluator, enforces every
  format rule above, and checks the network's outputs against the exact
  reference `F(isqrt(x)) mod 2^32` on `/app/probe_in.txt` and on **hidden
  vector files**.
- Runs `python3 /app/vecsim.py` on the same visible and hidden vector files
  and compares its JSON output to the same expected values.
- Checks `/app/probe_out.json` equals the expected output for the probe
  vectors.

Passing requires all of the above to hold.
