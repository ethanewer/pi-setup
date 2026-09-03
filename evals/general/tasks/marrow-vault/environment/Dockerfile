# marrow-vault — synchronous FIFO in Verilog, simulated with Icarus Verilog.
#
# Ships Icarus Verilog (iverilog + vvp) and one VISIBLE testbench the agent
# may run against its deliverable. The deliverable /app/rtl/sync_fifo.v is
# authored by the agent; nothing about the answer lives in the image.

FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        iverilog \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Visible fixture: a small testbench the agent can compile against its module.
COPY files/ /app/

# Toolchain smoke check: -g2005 must support $clog2 (used by the contract's
# count port and by every testbench).
RUN iverilog -V | head -2 \
 && printf '%s\n' 'module t(); localparam W = $clog2(64); reg [W:0] c; initial begin c = 64; $display("clog2-ok %d", c); end endmodule' > /tmp/clog2_check.v \
 && iverilog -g2005 -o /tmp/clog2_check.vvp /tmp/clog2_check.v \
 && vvp /tmp/clog2_check.vvp | grep -q clog2-ok \
 && mkdir -p /app/rtl /tmp/build