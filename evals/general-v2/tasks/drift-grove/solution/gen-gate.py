#!/usr/bin/env python3
"""Grove gate-network generator: compact XOR tree under a hard line cap.

usage: gen-gate.py <nbits> <out.def> [maxlines=32000]

Emit a netlist for XOR of nbits inputs using a balanced tree so the generated
definition always fits inside the simulator's line budget.
Format (sim-gates):
  INPUTS n
  g<k> XOR <a> <b>     a,b in 0..n-1 (input bit) or g<j> (earlier gate)
  OUT <wire>
"""
import sys


def main() -> int:
    nbits = int(sys.argv[1])
    out = sys.argv[2]
    maxlines = int(sys.argv[3]) if len(sys.argv) > 3 else 32000

    wires = [str(i) for i in range(nbits)]  # input bit ids
    gates = []
    # balanced pairing: fold from both ends so the net depth is ~log2(n)
    level = wires[:]
    gid = 0
    while len(level) > 1:
        nxt = []
        i = 0
        while i < len(level):
            if i + 1 < len(level):
                gates.append("g%d XOR %s %s" % (gid, level[i], level[i + 1]))
                nxt.append("g%d" % gid)
                gid += 1
                i += 2
            else:
                nxt.append(level[i])
                i += 1
        level = nxt

    total = gid + 2  # INPUTS line, OUT line
    if total > maxlines:
        print("OVER_BUDGET %d > %d" % (total, maxlines))
        return 1
    with open(out, "w") as fh:
        fh.write("INPUTS %d\n" % nbits)
        for line in gates:
            fh.write(line + "\n")
        fh.write("OUT %s\n" % level[0])
    print("wrote %d inputs, %d gates (%d lines) -> %s" % (nbits, gid, total, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())