`timescale 1ns/1ps
//
// marrow-vault hidden TB #3: htb_big.
//
// Generalization probe: instantiates the AGENT's /app/rtl/sync_fifo.v with
// NON-DEFAULT parameters (DATA_WIDTH=12, DEPTH=64) via parameter override.
// A module that hardcoded the default 8x8 geometry, skips initialization,
// or hardcodes observed behavior will diverge here. The same independent
// golden behavioral model compares dout/full/empty/count after every rising
// edge over a long fixed-seed mix: fill-to-full at depth 64, simultaneous
// ops at full and empty, deep wrap-around crossing the 64-slot boundary,
// LFSR-randomized traffic with mid-sequence synchronous reset pulses, and a
// final reuse-after-reset check.
//
module htb_big;

  parameter DATA_WIDTH = 12;
  parameter DEPTH      = 64;
  localparam PTR_W     = $clog2(DEPTH);

  reg                   clk   = 0;
  reg                   rst_n = 0;
  reg                   wr_en = 0;
  reg                   rd_en = 0;
  reg [DATA_WIDTH-1:0]  din   = 0;

  wire [DATA_WIDTH-1:0] dout;
  wire                  full;
  wire                  empty;
  wire [PTR_W:0]        count;

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

  // ---- Golden behavioral model (independent array/pointer/counter).
  reg [DATA_WIDTH-1:0] model_mem [0:DEPTH-1];
  integer              m_rd_ptr = 0;
  integer              m_wr_ptr = 0;
  integer              m_count  = 0;
  reg                  wr_ok, rd_ok;

  always @(posedge clk) begin
    if (!rst_n) begin
      m_rd_ptr = 0; m_wr_ptr = 0; m_count = 0;
    end else begin
      wr_ok = wr_en && (m_count != DEPTH);
      rd_ok = rd_en && (m_count != 0);
      if (wr_ok) begin
        model_mem[m_wr_ptr] = din;
        m_wr_ptr = (m_wr_ptr + 1) % DEPTH;
        m_count  = m_count + 1;
      end
      if (rd_ok) begin
        m_rd_ptr = (m_rd_ptr + 1) % DEPTH;
        m_count  = m_count - 1;
      end
    end
  end

  reg [31:0] lfsr = 32'h0F1E_2D3C;

  function [31:0] xorshift32;
    input [31:0] v;
    reg [31:0] t;
    begin
      t = v;
      t = t ^ (t << 13);
      t = t ^ (t >> 17);
      t = t ^ (t << 5);
      xorshift32 = t;
    end
  endfunction

  integer errors = 0;

  task check;
    begin
      if (count !== m_count) begin
        $display("HIDDEN_FAIL t=%0t count got=%0d want=%0d", $time, count, m_count);
        errors = errors + 1;
      end
      if (full !== (m_count == DEPTH)) begin
        $display("HIDDEN_FAIL t=%0t full got=%0b want=%0b", $time, full, (m_count == DEPTH));
        errors = errors + 1;
      end
      if (empty !== (m_count == 0)) begin
        $display("HIDDEN_FAIL t=%0t empty got=%0b want=%0b", $time, empty, (m_count == 0));
        errors = errors + 1;
      end
      if (m_count > 0 && dout !== model_mem[m_rd_ptr]) begin
        $display("HIDDEN_FAIL t=%0t dout got=%h want=%h (head)", $time, dout, model_mem[m_rd_ptr]);
        errors = errors + 1;
      end
    end
  endtask

  task edge_and_check;
    begin
      @(posedge clk);
      #7;
      check;
    end
  endtask

  task write_word;
    input [DATA_WIDTH-1:0] v;
    begin
      wr_en = 1'b1; rd_en = 1'b0; din = v;
      edge_and_check;
    end
  endtask

  task read_word;
    begin
      wr_en = 1'b0; rd_en = 1'b1; din = {DATA_WIDTH{1'b0}};
      edge_and_check;
    end
  endtask

  integer i;

  initial begin
    #400_000;
    $display("HIDDEN_FAIL watchdog timeout");
    $finish(2);
  end

  initial begin
    // ---- Reset (2 edges), verify empty.
    rst_n = 0; wr_en = 0; rd_en = 0;
    edge_and_check;
    edge_and_check;
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL reset wrong (big)");
      errors = errors + 1;
    end
    rst_n = 1;

    // ---- Directed fill to FULL at depth 64, ordered pattern (i*13)&0xFFF.
    for (i = 0; i < DEPTH; i = i + 1)
      write_word((i * 13) & 12'hFFF);
    if (full !== 1'b1 || count !== 64) begin
      $display("HIDDEN_FAIL fill-to-full at depth 64 wrong");
      errors = errors + 1;
    end

    // ---- Simultaneous r/w at full: write ignored, read accepted.
    begin : p_full_rw
      #2;   // pre-edge: dout must still show the head (stays valid)
      if (dout !== model_mem[m_rd_ptr]) begin
        $display("HIDDEN_FAIL pre-edge head wrong at full");
        errors = errors + 1;
      end
      wr_en = 1'b1; rd_en = 1'b1; din = 12'hABC;
      edge_and_check;
    end
    if (count !== 63 || dout !== ((1 * 13) & 12'hFFF)) begin
      $display("HIDDEN_FAIL r/w at full wrong");
      errors = errors + 1;
    end

    // ---- Simultaneous r/w at empty.
    repeat (63) read_word;          // empty
    wr_en = 1'b1; rd_en = 1'b1; din = 12'h5A5;
    edge_and_check;                 // only the write takes effect
    if (count !== 1 || empty !== 1'b0 || dout !== 12'h5A5) begin
      $display("HIDDEN_FAIL r/w at empty wrong");
      errors = errors + 1;
    end

    // ---- Long randomized mix (including near-full and near-empty drifts),
    //      with mid-sequence reset pulses.
    for (i = 0; i < 1500; i = i + 1) begin
      if ((m_count % 103) == 0) begin
        wr_en = 1'b1; rd_en = 1'b1;
        lfsr = xorshift32(lfsr);
        din = lfsr[31:20];
        edge_and_check;
      end else if ((m_count % 257) == 128) begin
        lfsr = xorshift32(lfsr);
        wr_en = 1'b1; rd_en = 1'b0; din = lfsr[31:20];
        edge_and_check;
      end else if ((i % 401) == 311) begin
        wr_en = 1'b0; rd_en = 1'b1; din = {DATA_WIDTH{1'b0}};
        edge_and_check;
      end else begin
        lfsr = xorshift32(lfsr);
        wr_en = lfsr[0];
        rd_en = lfsr[1] | lfsr[2];
        din   = lfsr[31:20];
        edge_and_check;
      end
      if ((i % 373) == 297) begin
        // synchronous reset pulse (2 edges), mid-stream
        rst_n = 0; wr_en = 0; rd_en = 0;
        edge_and_check;
        edge_and_check;
        rst_n = 1;
      end
    end

    // ---- Start the wrap analysis from a known-empty state.
    rst_n = 0; wr_en = 0; rd_en = 0;
    edge_and_check;
    edge_and_check;
    rst_n = 1;

    // ---- Deep wrap: fill 40, drain 20, fill 40 (crosses slot 63 -> 0),
    //      drain to empty; order is validated per cycle by the golden model.
    for (i = 0; i < 40; i = i + 1)
      write_word((i * 29 + 7) & 12'hFFF);
    for (i = 0; i < 20; i = i + 1) read_word;
    for (i = 0; i < 40; i = i + 1)
      write_word((i * 31 + 11) & 12'hFFF);
    if (count !== 60) begin
      $display("HIDDEN_FAIL wrap state wrong");
      errors = errors + 1;
    end
    for (i = 0; i < 60; i = i + 1) read_word;
    if (count !== 0 || empty !== 1'b1 || full !== 1'b0) begin
      $display("HIDDEN_FAIL final drain wrong");
      errors = errors + 1;
    end

    // ---- Reuse after reset with the non-default geometry.
    write_word(12'h111);
    write_word(12'h222);
    rst_n = 0; wr_en = 0; rd_en = 0;
    edge_and_check;
    rst_n = 1;
    write_word(12'h333);
    read_word;
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL reuse after reset wrong");
      errors = errors + 1;
    end

    if (errors == 0) $display("PASS_HIDDEN_htb_big");
    else             $display("HIDDEN_FAIL htb_big errors=%0d", errors);
    $finish;
  end

endmodule