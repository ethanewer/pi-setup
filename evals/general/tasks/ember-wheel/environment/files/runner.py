#!/usr/bin/env python3
"""Invoke the rebuilt native extension over vectors and emit a report.

Usage:
    python3 runner.py --input IN.json --output OUT.json

This harness is data-driven: it imports the compiled `snapvec` extension, folds
every vector in the input, and writes the per-vector checksums. It is correct as
shipped; any wrong checksum therefore comes from an unrepaired native.c.

Input format (IN.json):
    either a JSON array of vectors, or an object {"vectors": [...]}.
    Each vector is a (possibly empty) JSON array of unsigned integers in
    0 .. 2**32 - 1.

Output format (OUT.json):
    {"n_vectors": int, "checksums": ["<8 hex>", ...]}
    one 8-character lowercase hex checksum per input vector, in order.
"""
import argparse
import json
import sys

import snapvec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()

    with open(a.input) as f:
        data = json.load(f)
    vectors = data if isinstance(data, list) else data["vectors"]

    checksums = [snapvec.checksum(v) for v in vectors]
    report = {"n_vectors": len(checksums), "checksums": checksums}

    with open(a.output, "w") as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))


if __name__ == "__main__":
    sys.exit(main())