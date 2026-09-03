`timescale 1ns/1ps
//
// marrow-vault hidden TB #1: htb_rand.
//
// Compiles the AGENT's /app/rtl/sync_fifo.v (default DATA_WIDTH=8, DEPTH=8)
// together with this testbench and an independent golden behavioral model
// (array + pointer + counter) written purely from the documented semantics.
// Every observable output is compared against the golden model after EVERY
// rising edge. The stimulus is a fixed-seed xorshift32 LFSR (no $urandom, so
// runs are byte-for-byte reproducible) driving writes, reads, and
// simultaneous ops, interleaved with directed phases: fill-to-full,
// drain-to-empty, extra-ignored ops, and mid-sequence reset pulses.
//
module htb_rand;

  parameter DATA_WIDTH = 8;
  parameter DEPTH      = 8;
  localparam PTR_W     = $clog2(DEPTH);

  reg                  clk   = 0;
  reg                  rst_n = 0;
  reg                  wr_en = 0;
  reg                  rd_en = 0;
  reg [DATA_WIDTH-1:0] din   = 0;

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

  // ------------------------------------------------------------------
  // Golden behavioral model — a strictly independent second implementation.
  // ------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] model_mem [0:DEPTH-1];
  integer              m_rd_ptr = 0;
  integer              m_wr_ptr = 0;
  integer              m_count  = 0;
  reg                  wr_ok, rd_ok;

  always @(posedge clk) begin
    if (!rst_n) begin
      m_rd_ptr = 0; m_wr_ptr = 0; m_count = 0;
    end else begin
      // Legality is decided from the PRE-edge state; read-before-write: the
      // write goes to the free slot, the read consumes the old head.
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

  // ------------------------------------------------------------------
  // Fixed-seed deterministic stimulus generator (xorshift32).
  // ------------------------------------------------------------------
  reg [31:0] lfsr = 32'h4A9E_11C7;

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

  // Compare every observable against the golden model (call after settle).
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

  // One randomized step: advance the LFSR, drive inputs, clock, check.
  task random_step;
    begin
      lfsr = xorshift32(lfsr);
      wr_en = lfsr[0];
      rd_en = lfsr[1] | lfsr[2];      // bias toward simultaneous ops
      din   = lfsr[31:24];
      edge_and_check;
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

  task idle_cycle;
    begin
      wr_en = 1'b0; rd_en = 1'b0; din = {DATA_WIDTH{1'b0}};
      edge_and_check;
    end
  endtask

  // Watchdog in its OWN process: the scripted sequence below is bounded; if
  // anything stalls, fail loudly so the verifier never hangs.
  initial begin
    #250_000;
    $display("HIDDEN_FAIL watchdog timeout");
    $finish(2);
  end

  initial begin
    // ---- Phase 0: reset for two cycles, verify empty.
    rst_n = 0; wr_en = 0; rd_en = 0; din = {DATA_WIDTH{1'b0}};
    edge_and_check;
    edge_and_check;
    if (m_count !== 0 || count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL reset did not empty the FIFO");
      errors = errors + 1;
    end

    rst_n = 1;

    // ---- Phase 1: directed fill until FULL (values from the LFSR).
    repeat (DEPTH) begin
      lfsr = xorshift32(lfsr);
      write_word(lfsr[31:24]);
    end
    if (full !== 1'b1) begin
      $display("HIDDEN_FAIL full not asserted after DEPTH writes");
      errors = errors + 1;
    end

    // ---- Phase 2: writes while full are ignored.
    idle_cycle;
    lfsr = xorshift32(lfsr);
    write_word(lfsr[31:24]);
    if (count !== m_count || m_count !== DEPTH) begin
      $display("HIDDEN_FAIL write-when-full changed the FIFO");
      errors = errors + 1;
    end

    // ---- Phase 3: directed drain until EMPTY, then reads-while-empty.
    repeat (DEPTH) read_word;
    if (empty !== 1'b1 || count !== 0) begin
      $display("HIDDEN_FAIL empty not asserted after full drain");
      errors = errors + 1;
    end
    read_word;              // read while empty: ignored
    read_word;
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL read-when-empty changed the FIFO");
      errors = errors + 1;
    end

    // ---- Phase 4: long randomized mix, with a mid-sequence reset pulse.
    repeat (300) begin
      if ((m_count % 101) == 0) begin
        // occasional burst of all-simultaneous op cycles
        wr_en = 1'b1; rd_en = 1'b1;
        lfsr = xorshift32(lfsr);
        din = lfsr[31:24];
        edge_and_check;
      end
      random_step;
      if ((m_count % 211) == 97) begin
        // mid-sequence synchronous reset pulse (2 edges)
        rst_n = 0; wr_en = 0; rd_en = 0;
        edge_and_check;
        edge_and_check;
        rst_n = 1;
      end
    end

    // ---- Phase 5: random phase with heavy simultaneity only.
    repeat (600) begin
      lfsr = xorshift32(lfsr);
      wr_en = lfsr[0] | lfsr[3];
      rd_en = lfsr[1] | lfsr[2];
      din   = lfsr[31:24];
      edge_and_check;
    end

    // ---- Phase 6: partial drain, then re-fill (wrap-around), then drain.
    repeat (DEPTH / 2) read_word;
    repeat (DEPTH / 4) begin
      lfsr = xorshift32(lfsr);
      write_word(lfsr[31:24]);
    end
    repeat (m_count + 4) read_word;   // over-drain; must clamp at empty

    if (errors == 0) $display("PASS_HIDDEN_htb_rand");
    else             $display("HIDDEN_FAIL htb_rand errors=%0d", errors);
    $finish;
  end

endmodule