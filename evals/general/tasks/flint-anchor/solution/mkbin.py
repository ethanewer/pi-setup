#!/usr/bin/env python3
"""flint executable builder.

Assembles an emitted IR assembly file, links it against a project shared
library, and produces a runnable executable at a requested path. Used to
regenerate-and-run an executable from the emitted IR to validate it.

Usage:  python3 mkbin.py <ir.s> <libcore.so> <out>
"""
import os
import subprocess
import sys


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: mkbin.py <ir.s> <libcore.so> <out>\n")
        return 1
    ir, lib = argv[1], argv[2]
    out = os.path.abspath(argv[3])
    lib = os.path.abspath(lib)
    libdir = os.path.dirname(lib)

    # Assemble the IR and link it against the project shared library. -no-pie
    # keeps direct PLT calls simple; rpath makes the library resolvable at run
    # time wherever the executable is placed.
    cmd = [
        "gcc", "-no-pie", "-o", out,
        ir,
        "-L" + libdir, "-Wl,-rpath," + libdir,
        lib,
    ]
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
