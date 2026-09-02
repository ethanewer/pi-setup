`timescale 1ns/1ps
//
// tb3-agate-latch hidden TB #2: htb_edge.
//
// Scripted corner-case sweep (defaults DATA_WIDTH=8, DEPTH=8) against the
// AGENT's /app/rtl/sync_fifo.v, validated cycle-by-cycle by the same
// independent golden behavioral model as htb_rand. Pins the documented
// timing precisely: show-ahead dout, read-before-write visibility of the
// head (probed 2 ns before the clock edge), registered count, full/empty
// valid in the cycle after the causing operation, writes-while-full and
// reads-while-empty ignored, simultaneous read+write at full, empty, and
// count==1, wrap-around, and a mid-stream synchronous reset.
//
module htb_edge;

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

  // ---- Golden behavioral model (same semantics as the documentation).
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

  // Probe the value currently presented on dout 2 ns before the clock edge
  // (we are at edge+7 when called, so edge+9 still precedes the next edge at
  // edge+10). While the FIFO is non-empty this MUST equal the head model
  // word: it is the value a consumer samples during the current cycle
  // (show-ahead / read-before-write visibility).
  task probe_preedge_head;
    begin
      #2;
      if (m_count > 0 && dout !== model_mem[m_rd_ptr]) begin
        $display("HIDDEN_FAIL t=%0t pre-edge dout got=%h want=%h (read-before-write)", $time, dout, model_mem[m_rd_ptr]);
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

  // Simultaneous read+write (both requested; legality per the contract).
  task rw_word;
    input [DATA_WIDTH-1:0] v;
    begin
      probe_preedge_head;         // pin the value the read returns
      wr_en = 1'b1; rd_en = 1'b1; din = v;
      edge_and_check;
    end
  endtask

  initial begin
    #150_000;
    $display("HIDDEN_FAIL watchdog timeout");
    $finish(2);
  end

  initial begin
    // A. Reset clears everything (2 edges).
    rst_n = 0; wr_en = 0; rd_en = 0;
    edge_and_check;
    edge_and_check;
    if (count !== 0 || empty !== 1'b1 || full !== 1'b0) begin
      $display("HIDDEN_FAIL reset state wrong");
      errors = errors + 1;
    end
    rst_n = 1;

    // B. Writes into empty; show-ahead dout tracks the oldest word.
    write_word(8'h11);   // {11}
    write_word(8'h22);   // {11,22}
    write_word(8'h33);   // {11,22,33}
    write_word(8'h44);   // {11,22,33,44}
    if (count !== 4 || dout !== 8'h11) begin
      $display("HIDDEN_FAIL basic writes wrong");
      errors = errors + 1;
    end

    // C. Read consumes the head; dout shows the next head immediately.
    read_word;           // {22,33,44}
    read_word;           // {33,44}
    if (count !== 2 || dout !== 8'h33) begin
      $display("HIDDEN_FAIL reads wrong");
      errors = errors + 1;
    end

    // D. Simultaneous r/w at count==2: the OLD head 0x33 is read (probed
    //    pre-edge), 0xAA is stored at the TAIL; count stays 2, head 0x44.
    rw_word(8'hAA);      // {44,AA}
    if (count !== 2 || dout !== 8'h44) begin
      $display("HIDDEN_FAIL simultaneous at count 2 wrong");
      errors = errors + 1;
    end

    // E. One more read brings us to count==1, then simultaneous r/w at
    //    count==1: old head 0xAA read, 0x7F becomes the new head.
    read_word;           // {AA}
    rw_word(8'h7F);      // {7F}
    if (count !== 1 || dout !== 8'h7F) begin
      $display("HIDDEN_FAIL simultaneous at count 1 wrong");
      errors = errors + 1;
    end

    // F. Fill to full; whole-array wrap; extra writes ignored.
    write_word(8'h51);   // {7F,51}
    write_word(8'h52);   // {7F,51,52}
    write_word(8'h53);   // {7F,51,52,53}
    write_word(8'h54);   // {7F,51,52,53,54}
    write_word(8'h55);   // {7F,51,52,53,54,55}
    write_word(8'h56);   // {7F,51,52,53,54,55,56}
    write_word(8'h57);   // {7F,51,52,53,54,55,56,57} full
    if (full !== 1'b1 || count !== 8) begin
      $display("HIDDEN_FAIL fill-to-full wrong");
      errors = errors + 1;
    end
    write_word(8'h99);   // write while full: ignored
    if (count !== 8 || dout !== 8'h7F) begin
      $display("HIDDEN_FAIL write-when-full not ignored");
      errors = errors + 1;
    end

    // G. Simultaneous r/w at FULL: the write is ignored, the read proceeds.
    rw_word(8'hC0);      // {51,52,53,54,55,56,57}
    if (count !== 7 || dout !== 8'h51) begin
      $display("HIDDEN_FAIL simultaneous at full wrong");
      errors = errors + 1;
    end

    // H. Drain to empty; reads-while-empty ignored; dout unspecified there.
    read_word;           // {52,53,54,55,56,57}
    read_word;           // {53,54,55,56,57}
    read_word;           // {54,55,56,57}
    read_word;           // {55,56,57}
    read_word;           // {56,57}
    read_word;           // {57}
    read_word;           // {}
    if (empty !== 1'b1 || count !== 0) begin
      $display("HIDDEN_FAIL drain-to-empty wrong");
      errors = errors + 1;
    end
    read_word;           // read while empty: ignored
    read_word;
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL read-when-empty not ignored");
      errors = errors + 1;
    end

    // I. Simultaneous r/w at EMPTY: only the write takes effect.
    rw_word(8'h33);      // {33}
    if (count !== 1 || empty !== 1'b0 || dout !== 8'h33) begin
      $display("HIDDEN_FAIL simultaneous at empty wrong");
      errors = errors + 1;
    end

    // J. Wrap-around at the pointer boundary with order preservation:
    //    write 3A..3F, read 3A,3B, write 4A,4B,4C (crosses the wrap), drain.
    write_word(8'h3A);   // {33,3A}
    write_word(8'h3B);   // {33,3A,3B}
    write_word(8'h3C);   // {33,3A,3B,3C}
    write_word(8'h3D);   // {33,3A,3B,3C,3D}
    write_word(8'h3E);   // {33,3A,3B,3C,3D,3E}
    write_word(8'h3F);   // {33,3A,3B,3C,3D,3E,3F}
    read_word;           // {3A,3B,3C,3D,3E,3F}
    read_word;           // {3B,3C,3D,3E,3F}
    write_word(8'h4A);   // {3B,3C,3D,3E,3F,4A}
    write_word(8'h4B);   // {3B,3C,3D,3E,3F,4A,4B}
    write_word(8'h4C);   // {3B,3C,3D,3E,3F,4A,4B,4C} full (7 + 1 = 8)
    if (full !== 1'b1 || count !== 8) begin
      $display("HIDDEN_FAIL wrap-fill wrong");
      errors = errors + 1;
    end
    // Drain; expected order 3B 3C 3D 3E 3F 4A 4B 4C (validated per cycle).
    read_word; read_word; read_word; read_word;
    read_word; read_word; read_word; read_word;
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL wrap-drain wrong");
      errors = errors + 1;
    end

    // K. Mid-stream synchronous reset: two words first, then reset pulse,
    //    then confirm the FIFO is empty and usable again.
    write_word(8'h77);
    write_word(8'h88);
    if (count !== 2) begin
      $display("HIDDEN_FAIL pre-reset state wrong");
      errors = errors + 1;
    end
    rst_n = 0; wr_en = 0; rd_en = 0;
    edge_and_check;
    edge_and_check;
    if (count !== 0 || empty !== 1'b1 || full !== 1'b0) begin
      $display("HIDDEN_FAIL mid-stream reset wrong");
      errors = errors + 1;
    end
    rst_n = 1;
    probe_preedge_head;
    write_word(8'hAB);   // {AB}
    read_word;           // {}
    if (count !== 0 || empty !== 1'b1) begin
      $display("HIDDEN_FAIL post-reset reuse wrong");
      errors = errors + 1;
    end

    if (errors == 0) $display("PASS_HIDDEN_htb_edge");
    else             $display("HIDDEN_FAIL htb_edge errors=%0d", errors);
    $finish;
  end

endmodule