#!/usr/bin/env python3
"""generate.py -- greedy target-sequence generation for the vine-pier model.

Runs the target model defined by a shipped checkpoint to produce a fixed-count,
deterministic greedy continuation from a prompt (always >= 2 token ids).

Usage:
  python3 generate.py --ckpt <checkpoint.ckpt> [--prompt a,b,...] [--out FILE]

If --prompt is omitted it defaults to the shipped active prompt. Writes the
greedy result as JSON to --out (default /app/greedy_out.json).
"""
import argparse
import json
import struct
import numpy as np


def load_ckpt(path):
    b = open(path, "rb").read()
    o = 8
    V = struct.unpack_from("<I", b, o)[0]; o += 4
    nt = struct.unpack_from("<I", b, o)[0]; o += 4
    mg = struct.unpack_from("<I", b, o)[0]; o += 4
    de = struct.unpack_from("<I", b, o)[0]; o += 4
    rl = struct.unpack_from("<I", b, o)[0]; o += 4
    rev = b[o:o + rl].decode("ascii"); o += rl
    ts = {}
    for _ in range(nt):
        nl = struct.unpack_from("<I", b, o)[0]; o += 4
        nm = b[o:o + nl].decode("ascii"); o += nl
        dt = struct.unpack_from("<B", b, o)[0]; o += 1
        nd = struct.unpack_from("<B", b, o)[0]; o += 1
        shp = struct.unpack_from("<%dI" % nd, b, o); o += 4 * nd
        n = int(np.prod(shp))
        ts[nm] = np.frombuffer(b[o:o + 4 * n], dtype="float32").reshape(shp).copy()
        o += 4 * n
    return {"rev": rev, "tensors": ts, "max_gen": mg}


def argmax_next(WB, a, b):
    """argmax over last axis; ties break toward the lowest index."""
    return int(np.argmax(WB[a, b]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt", default=None, help="comma-separated token ids")
    ap.add_argument("--out", default="/app/greedy_out.json")
    args = ap.parse_args()

    ck = load_ckpt(args.model)
    W, B = ck["tensors"]["W"], ck["tensors"]["B"]
    WB = W + B[None, None, :]

    if args.prompt is None:
        prompt = [2, 4]
    else:
        prompt = [int(x) for x in args.prompt.split(",") if x != ""]
    if len(prompt) < 2:
        raise ValueError("prompt must be at least 2 token ids")

    seq = list(prompt)
    for _ in range(ck["max_gen"]):
        seq.append(argmax_next(WB, seq[-2], seq[-1]))

    result = {
        "ckpt": args.model,
        "revision": ck["rev"],
        "prompt": prompt,
        "continuation": seq[len(prompt):],
        "full": seq,
        "max_gen": ck["max_gen"],
    }
    with open(args.out, "w") as fh:
        json.dump(result, fh)
    print(json.dumps({"continuation": result["continuation"]}))


def argmax_next(WB, a, b):
    return int(np.argmax(WB[a, b]))

if __name__ == "__main__":
    main()
