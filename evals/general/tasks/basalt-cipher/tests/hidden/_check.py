#!/usr/bin/env python3
"""Verifier helper for basalt-cipher hidden cases.

Reads tests/hidden/case*.json (each a list of {"name","argv"}), computes an
independent reference (identical cipher math and exit-code semantics as the C
binary) and compares against the bare `prog` binary (resolved via PATH) for
exit code and exact stdout bytes. Prints ALL_HIDDEN_OK and exits 0 when every
candidate matches.
"""
import glob, json, os, shutil, subprocess, sys

def dec(s):
    if len(s) % 2:
        return None
    try:
        return bytes.fromhex(s)
    except ValueError:
        return None

def oracle(argv):
    if len(argv) != 3:
        return (1, b"")
    mode, key, data = argv
    if mode not in ("xor", "skip"):
        return (1, b"")
    k = dec(key)
    if k is None:
        return (2, b"")
    d = dec(data)
    if d is None:
        return (2, b"")
    m = len(k); n = len(d)
    if m == 0:
        return (2, b"")
    if n == 0:
        return (0, b"\n")
    if mode == "xor":
        out = bytes(d[i] ^ k[i % m] for i in range(n))
    else:
        out = bytes((d[i] + (k[(i*3) % m] * ((i % 8) + 1))) & 0xFF for i in range(n))
    return (0, out.hex().encode() + b"\n")

def main():
    d = sys.argv[1]
    files = sorted(glob.glob(os.path.join(d, "case*.json")))
    if not files:
        print("NO_HIDDEN_CASES")
        return 1
    prog = shutil.which("prog")
    if not prog:
        print("PROG_NOT_ON_PATH")
        return 1
    mism = 0; total = 0
    for f in files:
        for cand in json.load(open(f)):
            argv = cand["argv"]
            total += 1
            want_rc, want_out = oracle(argv)
            e = subprocess.run([prog] + argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            if e.returncode != want_rc or e.stdout != want_out:
                mism += 1
                print("MISMATCH name=%s argv=%s rc=%d want=%d out=%r want=%r" %
                      (cand.get("name","?"), argv, e.returncode, want_rc, e.stdout, want_out))
    if mism == 0:
        print("ALL_HIDDEN_OK cases=%d" % total)
        return 0
    print("HIDDEN_FAIL=%d/%d" % (mism, total))
    return 1

if __name__ == "__main__":
    sys.exit(main())