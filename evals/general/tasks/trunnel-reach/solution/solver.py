#!/usr/bin/env python3
"""Reference solver for the trunnel-reach crackme family.

Usage: python3 solver.py <path-to-crackme-binary>
Prints the 16 bytes that make that binary print ACCESS GRANTED, then a newline.
"""
import sys

import angr
import claripy

NBYTES = 16


def solve(path: str) -> bytes:
    proj = angr.Project(path, auto_load_libs=False)
    inp = claripy.BVS("pw", NBYTES * 8)
    state = proj.factory.full_init_state(stdin=inp)
    # The program rejects non-printable bytes; constrain the input up front so
    # the exploration never dwells on impossible branches.
    for i in range(NBYTES):
        b = inp.get_byte(i)
        state.solver.add(b >= 0x20, b <= 0x7E)
    sm = proj.factory.simulation_manager(state)

    def granted(s):
        try:
            return b"ACCESS GRANTED" in s.posix.dumps(1)
        except Exception:
            return False

    sm.explore(find=granted, num_find=1)
    if not sm.found:
        # Fall back: the success path exits, so scan everything that died.
        for s in sm.deadended:
            if granted(s):
                sm.found.append(s)
                break
    if not sm.found:
        raise SystemExit("no success state found for %s" % path)
    return sm.found[0].posix.dumps(0)[:NBYTES]


if __name__ == "__main__":
    got = solve(sys.argv[1])
    sys.stdout.buffer.write(got)
    sys.stdout.buffer.write(b"\n")