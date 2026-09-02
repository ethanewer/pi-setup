# Agate-Latch: a parametrized synchronous FIFO in Verilog

Author a single synthesizable Verilog module, `sync_fifo`, and prove it under
Icarus Verilog (already installed in this container). The module is a
synchronous (same-clock) FIFO with a registered element counter, combinational
show-ahead read output, and read-before-write visibility of the head.

## Environment

- Icarus Verilog is installed; use `iverilog` to compile and `vvp` to
  simulate. No other toolchain, no network access.
- Work in `/app`. Your deliverable is exactly one file:

  - `/app/rtl/sync_fifo.v` — the FIFO module.
  - `/app/tb/sanity_tb.v` — a small visible testbench is already shipped there
    (read it; it documents the observable timing via concrete expectations).

## Module contract (exact)

File `/app/rtl/sync_fifo.v` must define a module with EXACTLY this signature:

```verilog
module sync_fifo #(
    parameter DATA_WIDTH = 8,   // word width in bits
    parameter DEPTH      = 8    // number of slots; guaranteed a power of two
) (
    input  wire                  clk,    // rising-edge clock
    input  wire                  rst_n,  // active-low SYNCHRONOUS reset
    input  wire                  wr_en,  // write request
    input  wire                  rd_en,  // read request
    input  wire [DATA_WIDTH-1:0] din,    // write data
    output wire [DATA_WIDTH-1:0] dout,   // current head word (show-ahead)
    output wire                  full,   // count == DEPTH
    output wire                  empty,  // count == 0
    output reg  [$clog2(DEPTH):0] count  // number of stored words
);
```

The parameters must actually be used: the storage array must index
`0..DEPTH-1` and the data path must be `DATA_WIDTH` bits wide, so that an
instance with overridden `DEPTH`/`DATA_WIDTH` works. Compile everything with
`iverilog -g2005` (this is what the grader uses), which supports
`$clog2`.

## Semantics and exact timing

All state transitions happen on the **rising edge of `clk`**; nothing else
changes state. Read the following carefully — a golden behavioral model in the
testbench compares every observable output against your module cycle by cycle.

1. **Reset.** When `rst_n` is low at a rising edge, the FIFO becomes empty:
   `count` becomes 0, `rd_ptr`/`wr_ptr` are cleared, and `full=0`, `empty=1`.
   Reset is synchronous; it only takes effect on the clock edge. Apply `rst_n`
   low for at least two clock cycles at the start of your own tests.
2. **Write.** If `wr_en` is high at a rising edge while the FIFO is **not
   full**, `din` is stored at the current write slot, the write pointer
   advances (with wraparound), and `count` increments. A write while **full**
   is ignored completely (no state change, including `count`).
3. **Read / `dout`.** `dout` is a *show-ahead* output: it is a combinational
   function of the internal state and always presents the **oldest stored
   word** (the word at the read pointer). When `rd_en` is high at a rising
   edge while the FIFO is **not empty**, the oldest word is consumed: the read
   pointer advances. After an accepted read, `dout` immediately (in the same
   simulated time, combinationally) presents the *next* oldest word. A read
   while **empty** is ignored. **While the FIFO is empty the value of `dout`
   is unspecified**; graders never compare it in empty cycles (consumers must
   check `empty` first).
4. **Read-before-write visibility.** When `rd_en` and `wr_en` are both high at
   the same rising edge, each takes effect **if and only if it is legal
   (pre-edge legal checks)**: the read consumes the *old* head word, and the
   write stores `din` into the free slot — the two operations never see each
   other. Specifically:
   - both legal (count between 1 and `DEPTH-1`): head is consumed, `din` is
     stored, `count` stays unchanged; afterwards `dout` shows the new head.
   - empty at the edge: only the write takes effect (read is ignored).
   - full at the edge: only the read takes effect (write is ignored).
   - `count == 1` at the edge: the *old* head is read (the value that was on
     `dout` before the edge) and the written word becomes the new head.
5. **`count`, `full`, `empty` timing.** `count` is a **registered** output:
   it holds the post-edge number of stored words, valid throughout the cycle
   after each rising edge. `full` and `empty` are functions of that registered
   count (`full == (count == DEPTH)`, `empty == (count == 0)`); they may be
   written either as combinational assigns of `count` or as registered regs —
   the observable requirement is that *after every rising edge*
   `full`/`empty` equal the predicates of the updated `count` (i.e. flags are
   valid one cycle after the operation that caused them).
6. **Wraparound.** The FIFO is circular; storage slots are reused after a full
   sweep of `DEPTH` slots. A correct implementation must preserve FIFO order
   across any interleaving of writes and reads, including wrap-around in the
   middle of a sequence.

## How to build and test (agent loop)

```bash
cd /app
iverilog -g2005 -o /tmp/build/sanity.vvp rtl/sync_fifo.v tb/sanity_tb.v
vvp /tmp/build/sanity.vvp        # prints SANITY_PASS when your module is sane
```

`/app/tb/sanity_tb.v` drives a fixed mixture of writes, reads, simultaneous
operations, fill-to-full, drain-to-empty, and a couple of resets, checking
`count`/`full`/`empty`/`dout` after each rising edge. Use it as your
development harness; keep editing `/app/rtl/sync_fifo.v` until it prints
`SANITY_PASS` (you may also write your own throwaway testbenches in `/tmp`).

## How it will be graded

The grader compiles *your* `/app/rtl/sync_fifo.v` together with **hidden**
testbenches (mounted only at grading time) and runs each with vvp:

```
iverilog -g2005 -o /tmp/tb.vvp <hidden_tb.v> /app/rtl/sync_fifo.v
vvp /tmp/tb.vvp
```

Each hidden testbench embeds an **independent golden behavioral model** (a
separate array/pointer model written from the semantics above) and compares
`dout`, `full`, `empty`, and `count` against it after **every** rising edge,
over hundreds to thousands of cycles. The hidden set covers: fixed-seed
randomized directed sequences; write-when-full; read-when-empty; simultaneous
read+write at full, empty, and `count == 1`; mid-sequence resets;
wrap-around at both small and large depths; and **non-default parameters**
(e.g. `DEPTH=64`, `DATA_WIDTH=12` via parameter override). A module that
"passes" only the visible sanity testbench (hardcoded values, fixed-depth
storage, ignored inputs, off-by-one count, missing reset) will fail the hidden
tests. Keep your simulation runtime small (< 1 s per testbench) — nothing
about this task needs long runs.

## Constraints

- Only standard language / Icarus Verilog, no network, no external packages.
- Single deliverable file: `/app/rtl/sync_fifo.v`.
- Deterministic, synthesizable-style RTL (no `#` delays, no timing control
  inside your module; use nonblocking assignments for all registered state).