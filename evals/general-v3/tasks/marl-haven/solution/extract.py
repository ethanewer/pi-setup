#!/usr/bin/env python3
"""Oracle extraction program for marl-haven: decodes an SBT-1 capture, applies
the frame/channel query, and saves the recovered matrix as a float64 .npy.
Rows = selected frames (query order), columns = selected channels (query
order). Standard library + numpy only."""
import struct
import sys

import numpy as np


def parse_spec(spec):
    """Expand a query spec: comma-separated tokens, each a non-negative int or
    an inclusive a-b range (normalized). Duplicates honored, order preserved."""
    idx = []
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if "-" in tok:
            a, b = tok.split("-", 1)
            lo, hi = sorted((int(a), int(b)))
            idx.extend(range(lo, hi + 1))
        else:
            idx.append(int(tok))
    return idx


def decode_capture(path):
    """Return the list of true-value rows for the VALID frames in file order."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"SBTF":
        raise ValueError("bad magic")
    version, key, flags = struct.unpack(">HBB", data[4:8])
    (n,) = struct.unpack(">I", data[8:12])
    channels, _reserved = struct.unpack(">HH", data[12:16])
    frame_size = 9 + 2 * channels
    rows = []
    off = 16
    for _ in range(n):
        _ts, status = struct.unpack_from(">QB", data, off)
        payload = bytes(b ^ key for b in data[off + 9: off + frame_size])
        off += frame_size
        if status != 1:
            continue
        samples = list(struct.unpack(">" + "h" * channels, payload))
        if (flags & 1) and rows:
            prev = rows[-1]
            rows.append([prev[c] + samples[c] for c in range(channels)])
        else:
            rows.append(samples)
    return rows


def load_query(path):
    spec = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            k, _, v = line.partition("=")
            spec[k.strip()] = v.strip()
    return spec


def build_matrix(capture_path, query_path):
    rows = decode_capture(capture_path)
    spec = load_query(query_path)
    cidx = parse_spec(spec["channels"])
    fidx = parse_spec(spec["frames"])
    selected = [rows[i] for i in fidx if 0 <= i < len(rows)]
    matrix = np.empty((len(selected), len(cidx)), dtype=np.float64)
    for r, row in enumerate(selected):
        for c, ci in enumerate(cidx):
            matrix[r, c] = row[ci]
    return matrix


def main():
    if len(sys.argv) != 4:
        print("usage: extract.py <capture> <query> <out_npy>", file=sys.stderr)
        return 2
    matrix = build_matrix(sys.argv[1], sys.argv[2])
    np.save(sys.argv[3], matrix)
    return 0


if __name__ == "__main__":
    sys.exit(main())
