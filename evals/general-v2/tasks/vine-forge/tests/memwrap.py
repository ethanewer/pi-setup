#!/usr/bin/env python3
"""Memory-measuring wrapper for the vine-forge verifier.

Runs the given command (a bag grader) as a child process, polls the child's
VmHWM from /proc, and prints "PEAK_KB <int>" on stdout. Exits with the
child's return code. Kept tiny so its own RSS does not matter.

Usage: python3 /tests/memwrap.py <script> [args...]
"""
import subprocess
import sys
import time


def main():
    if len(sys.argv) < 2:
        print("PEAK_KB -1")
        return 2
    cmd = [sys.executable] + sys.argv[1:]
    proc = subprocess.Popen(cmd)
    peak = 0
    while proc.poll() is None:
        try:
            with open("/proc/%d/status" % proc.pid) as fh:
                for line in fh:
                    if line.startswith("VmHWM:"):
                        peak = max(peak, int(line.split()[1]))
                        break
        except OSError:
            pass
        time.sleep(0.05)
    rc = proc.wait()
    if peak <= 0:
        import resource
        peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    print("PEAK_KB %d" % peak)
    return rc


if __name__ == "__main__":
    sys.exit(main())
