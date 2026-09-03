#!/bin/bash
#
# marrow-vault oracle. Authors /app/rtl/sync_fifo.v: a parametrized
# synchronous FIFO with a registered count, combinational show-ahead dout,
# and read-before-write visibility of the head. Then self-checks by compiling
# the deliverable against the visible testbench shipped in the image
# (/app/tb/sanity_tb.v) and requiring SANITY_PASS. Never reads /tests.
set -euo pipefail

mkdir -p /app/rtl

cat > /app/rtl/sync_fifo.v <<'EOF'
// marrow-vault: synchronously clocked FIFO with show-ahead read output.
//
// Contract (single clock domain, everything on the rising edge of clk):
//   - rst_n low at a rising edge  -> FIFO empties: count=0, pointers cleared.
//   - wr_en && !full              -> din stored at the write slot; count+1.
//   - rd_en && !empty             -> oldest word consumed; count-1.
//   - simultaneous wr/rd both act when both are legal (pre-edge legality);
//     at count==1 the OLD head is read and the written word becomes the
//     new head.
//   - dout = mem[rd_ptr] (combinational, show-ahead; unspecified when empty).
//   - full/empty are predicates of the registered count (valid the cycle
//     after the operation that caused them).
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire                  rd_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  full,
    output wire                  empty,
    output reg  [$clog2(DEPTH):0] count
);
    localparam PTR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0]      rd_ptr;   // read pointer (head slot)
    reg [PTR_W-1:0]      wr_ptr;   // write pointer (next free slot)

    // Legality is decided on the PRE-edge state (pre-edge count), so a
    // simultaneous read+write at count==1 reads the old head and stores the
    // new word into the slot the head is leaving from the reader's point of
    // view -- the written word becomes the next head.
    wire wr_ok = wr_en && (count != DEPTH);
    wire rd_ok = rd_en && (count != 0);

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= {PTR_W{1'b0}};
            wr_ptr <= {PTR_W{1'b0}};
            count  <= 0;
        end else begin
            if (wr_ok) begin
                mem[wr_ptr] <= din;          // nonblocking: read-before-write
                wr_ptr      <= wr_ptr + 1'b1; // wraps mod 2^PTR_W
            end
            if (rd_ok)
                rd_ptr <= rd_ptr + 1'b1;
            count <= count + (wr_ok ? 1'b1 : 1'b0) - (rd_ok ? 1'b1 : 1'b0);
        end
    end

    // Show-ahead head output; unspecified while empty (consumers gate on
    // empty). Read-before-write holds because the write uses a nonblocking
    // assignment, so dout keeps presenting the pre-edge head during the
    // cycle in which a simultaneous write lands.
    assign dout  = mem[rd_ptr];
    assign full  = (count == DEPTH);
    assign empty = (count == 0);

endmodule
EOF

chmod 644 /app/rtl/sync_fifo.v

# ---- self-check: compile the deliverable with the visible testbench.
if [ ! -d /tmp/build ]; then mkdir -p /tmp/build; fi
iverilog -g2005 -o /tmp/build/sanity.vvp /app/rtl/sync_fifo.v /app/tb/sanity_tb.v
out="$(vvp /tmp/build/sanity.vvp 2>&1)"
if ! printf '%s\n' "$out" | grep -q 'SANITY_PASS'; then
    printf '%s\n' "$out" >&2
    echo "agate-latch oracle: deliverable failed the visible sanity testbench" >&2
    exit 1
fi

echo "agate-latch oracle complete -> /app/rtl/sync_fifo.v (sanity PASS)"