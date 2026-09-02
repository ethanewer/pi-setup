#!/usr/bin/env python3
"""Build deterministic input fixtures for prism-atlas.

Reads no hidden/tests. Writes:
  <dest>/data/calls/{a,b,c}.log   - call-site signature logs (part 1)
  <dest>/data/rows/depot-*.txt    - plain-text rows for the vim pass (part 4)
  <dest>/state/state.txt          - initial persistent-state value (part 2/3)

Every fixture line is defined here so the host can reproduce it byte-for-byte.
"""
import os
import sys


def main(dest: str) -> int:
    # ---------------- call-site signature logs (part 1) ----------------
    # Distinct signatures and how many times each appears (one occurrence per
    # entry line). A few "noise" lines (blank, whitespace-only, trailing
    # space, and CRLF endings) are mixed in to exercise the strip/ignore rule.
    counts = {
        "alpha_pipe": 7,
        "beta_splice": 6,
        "delta_wave": 5,
        "gamma_link": 5,
        "epsilon_fuse": 3,
        "zeta_bolt": 3,
        "eta_trellis": 2,
        "iota_fan": 2,
        "theta_guard": 2,
        "kappa_probe": 1,
        "lambda_moor": 1,
    }
    lines = []
    for token, n in counts.items():
        lines.extend([token] * n)
    # noise / edge lines (empty & whitespace-only are ignored; trailing
    # whitespace and CRLF must be stripped before counting).
    lines.append("")                       # empty line (ignored)
    lines.append("   ")                    # whitespace-only (ignored)
    lines.append("")                       # empty line (ignored)
    lines.append("delta_wave  ")           # trailing spaces
    lines.append("epsilon_fuse \t")        # trailing tab
    lines.append("eta_trellis")            # CRLF ending (below)
    lines.append("theta_guard")            # CRLF ending (below)

    # (content, line-ending) pairs; the two CRLF ones get a carriage return.
    paired = [(ln, "\r\n" if ln == "eta_trellis" or ln == "theta_guard" else "\n")
              for ln in lines]

    # Chunk round-robin across three log files (order within a file is
    # irrelevant to ranking; only aggregate counts matter).
    files = {"a.log": [], "b.log": [], "c.log": []}
    names = list(files)
    for i, (content, ending) in enumerate(paired):
        files[names[i % len(names)]].append((content, ending))

    base = os.path.join(dest, "app", "data", "calls")
    os.makedirs(base, exist_ok=True)
    for name, items in files.items():
        with open(os.path.join(base, name), "w", newline="") as fh:
            for content, ending in items:
                fh.write(content + ending)

    # ---------------- depot rows for the vim pass (part 4) ----------------
    rows = {
        "depot-a.txt": [
            "104|Meridian depot|2207",
            "110|Beryllium latch|830",
        ],
        "depot-b.txt": [
            "77|south plinth|410",
            "131|Garbled mast|610",
        ],
        "depot-c.txt": [
            "9|Single tower hall|304",
        ],
        "depot-d.txt": [
            # malformed rows are left byte-identical by the macro:
            "  |Misaligned|",          # empty first field
            "three|pipes|only|extra",  # too many fields
            "sparse|one",              # too few fields
            "",                        # empty line
            "52|Apex winch|88",     # a valid row
        ],
    }
    rbase = os.path.join(dest, "app", "data", "rows")
    os.makedirs(rbase, exist_ok=True)
    for name, rows in rows.items():
        with open(os.path.join(rbase, name), "w") as f:
            for r in rows:
                f.write(r + "\n")

    # ---------------- initial persistent state (part 2/3) ----------------
    sbase = os.path.join(dest, "app", "state")
    os.makedirs(sbase, exist_ok=True)
    with open(os.path.join(sbase, "state.txt"), "w") as f:
        f.write("17\n")

    return 0


if __name__ == "__main__":
    dest = sys.argv[1] if len(sys.argv) > 1 else "/"
    sys.exit(main(dest))