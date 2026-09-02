`timescale 1ns/1ps
//
// tb3-agate-latch sanity testbench (VISIBLE fixture — shipped in the image).
//
// Drives a fixed mixture of writes, reads, simultaneous ops, fill-to-full,
// drain-to-empty, and resets, and checks count/full/empty/dout after every
// clock edge against hand-computed expectations. Prints SANITY_PASS at the
// end if every check held. While the FIFO is empty, dout is unspecified and
// is not compared (per the documented contract).
//
// Compile + run (from /app):
//     iverilog -g2005 -o /tmp/build/sanity.vvp rtl/sync_fifo.v tb/sanity_tb.v
//     vvp /tmp/build/sanity.vvp
//
module sanity_tb;

  parameter DATA_WIDTH = 8;
  parameter DEPTH      = 8;

  reg                      clk   = 0;
  reg                      rst_n = 0;
  reg                      wr_en = 0;
  reg                      rd_en = 0;
  reg [DATA_WIDTH-1:0]     din   = 0;

  wire [DATA_WIDTH-1:0]    dout;
  wire                     full;
  wire                     empty;
  wire [$clog2(DEPTH):0]   count;

  sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) u_fifo (
      .clk  (clk),
      .rst_n(rst_n),
      .wr_en(wr_en),
      .rd_en(rd_en),
      .din  (din),
      .dout (dout),
      .full (full),
      .empty(empty),
      .count(count)
  );

  always #5 clk = ~clk;

  integer errors = 0;

  // Check after a rising edge has settled (t = edge + 7ns).
  task check;
    input integer           exp_count;
    input reg               exp_empty;
    input reg               exp_full;
    input [DATA_WIDTH-1:0]  exp_dout;   // only used when exp_count > 0
    begin
      if (count !== exp_count) begin
        $display("SANITY_CHECK_FAIL t=%0t count got=%0d want=%0d", $time, count, exp_count);
        errors = errors + 1;
      end
      if (empty !== exp_empty) begin
        $display("SANITY_CHECK_FAIL t=%0t empty got=%0b want=%0b", $time, empty, exp_empty);
        errors = errors + 1;
      end
      if (full !== exp_full) begin
        $display("SANITY_CHECK_FAIL t=%0t full got=%0b want=%0b", $time, full, exp_full);
        errors = errors + 1;
      end
      if (exp_count > 0 && dout !== exp_dout) begin
        $display("SANITY_CHECK_FAIL t=%0t dout got=%h want=%h", $time, dout, exp_dout);
        errors = errors + 1;
      end
    end
  endtask

  // Drive the inputs for a cycle, wait for the edge, settle, then check.
  task step;
    input reg        n_wr_en;
    input reg        n_rd_en;
    input [DATA_WIDTH-1:0] n_din;
    input integer    exp_count;
    input reg        exp_empty;
    input reg        exp_full;
    input [DATA_WIDTH-1:0] exp_dout;
    begin
      wr_en = n_wr_en;
      rd_en = n_rd_en;
      din   = n_din;
      @(posedge clk);
      #7;
      check(exp_count, exp_empty, exp_full, exp_dout);
    end
  endtask

  // Sequence: two reset edges, then the pattern below (designed from the
  // documented semantics; expected values recomputed by hand).
  //  - 0xAB, 0xCD, 0xEF written;  - simultaneous writes/reads;
  //  - fill to full;               - drain to empty;
  //  - simultaneous at full/empty; - wrap-around; - mid-stream reset.
  initial begin
    // Reset low for two cycles.
    rst_n = 0; wr_en = 0; rd_en = 0;
    @(posedge clk); #7; check(0, 1'b1, 1'b0, 8'h00);
    @(posedge clk); #7; check(0, 1'b1, 1'b0, 8'h00);

    rst_n = 1;
    // Writes into empty.
    step(1, 0, 8'hAB, 1, 1'b0, 1'b0, 8'hAB);   // count 1, dout AB
    step(1, 0, 8'hCD, 2, 1'b0, 1'b0, 8'hAB);   // count 2, dout AB (oldest)
    step(1, 0, 8'hEF, 3, 1'b0, 1'b0, 8'hAB);   // count 3

    // Simultaneous read+write at count 3: read AB, store 0x12; count stays 3.
    step(1, 1, 8'h12, 3, 1'b0, 1'b0, 8'hCD);   // dout advances to CD

    // Reads only: the 0x12 read empties the FIFO.
    step(0, 1, 8'h00, 2, 1'b0, 1'b0, 8'hEF);
    step(0, 1, 8'h00, 1, 1'b0, 1'b0, 8'h12);

    // Read-while-empty (ignored; dout now unspecified).
    step(0, 1, 8'h00, 0, 1'b1, 1'b0, 8'h00);

    // Simultaneous at empty: only the write takes effect.
    step(1, 1, 8'h7E, 1, 1'b0, 1'b0, 8'h7E);

    // Fill to full: 7 more writes (0x33..0x39).
    step(1, 0, 8'h33, 2, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h34, 3, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h35, 4, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h36, 5, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h37, 6, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h38, 7, 1'b0, 1'b0, 8'h7E);
    step(1, 0, 8'h39, 8, 1'b0, 1'b1, 8'h7E);   // full: count 8

    // Simultaneous at full: write 0x41 ignored, read 0x7E accepted.
    step(1, 1, 8'h41, 7, 1'b0, 1'b0, 8'h33);   // count 7, dout 33

    // Wrap-around: two reads, then five writes crossing the pointer wraparound.
    step(0, 1, 8'h00, 6, 1'b0, 1'b0, 8'h34);
    step(0, 1, 8'h00, 5, 1'b0, 1'b0, 8'h35);
    step(1, 0, 8'hB1, 6, 1'b0, 1'b0, 8'h35);
    step(1, 0, 8'hB2, 7, 1'b0, 1'b0, 8'h35);
    step(1, 0, 8'hB3, 8, 1'b0, 1'b1, 8'h35);   // full again

    // Drain everything; read-back order: 35 36 37 38 39 B1 B2 B3.
    step(0, 1, 8'h00, 7, 1'b0, 1'b0, 8'h36);
    step(0, 1, 8'h00, 6, 1'b0, 1'b0, 8'h37);
    step(0, 1, 8'h00, 5, 1'b0, 1'b0, 8'h38);
    step(0, 1, 8'h00, 4, 1'b0, 1'b0, 8'h39);
    step(0, 1, 8'h00, 3, 1'b0, 1'b0, 8'hB1);
    step(0, 1, 8'h00, 2, 1'b0, 1'b0, 8'hB2);
    step(0, 1, 8'h00, 1, 1'b0, 1'b0, 8'hB3);
    step(0, 1, 8'h00, 0, 1'b1, 1'b0, 8'h00);   // empty

    // Mid-stream reset: write two, reset for two cycles, verify cleared.
    step(1, 0, 8'h51, 1, 1'b0, 1'b0, 8'h51);
    rst_n = 0; wr_en = 0; rd_en = 0;
    @(posedge clk); #7; check(0, 1'b1, 1'b0, 8'h00);
    @(posedge clk); #7; check(0, 1'b1, 1'b0, 8'h00);

    if (errors == 0)
      $display("SANITY_PASS");
    else
      $display("SANITY_FAIL errors=%0d", errors);
    $finish;
  end

endmodule