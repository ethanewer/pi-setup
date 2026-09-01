#!/usr/bin/env python3
"""Independent reference for marl-haven: re-derives the expected matrix from
any SBT-1 capture + query, without using the agent's code."""
import struct


def parse_spec(spec):
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
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"SBTF":
        raise ValueError("bad magic")
    _version, key, flags = struct.unpack(">HBB", data[4:8])
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


def expected_matrix(capture_path, query_path):
    import numpy as np

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
