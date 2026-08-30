#!/usr/bin/env python3
"""speculative.py -- draft-and-verify loop against a target sequence.

Broken into fixed-length draft blocks drawn from the draft model tensor "D",
each proposed token is compared against the target sequence up to the first
mismatch; the matching prefix is accepted into the growing context, and when a
proposed token disagrees the true (next) target token is appended as the
verified token and the loop resumes from the extended context.

Usage:
  python /app/speculative.py --model <ck> --prefix a,b,c --target t1,t2,... [--draft K] [--out FILE]
Result written as JSON to --out (default /app/spec_out.json).
"""
import argparse
import json
import struct
import numpy as np


def load_tensors(path):
    b = open(path, "rb").read()
    off = 8
    V = struct.unpack_from("<I", b, off)[0]; off += 4
    nt = struct.unpack_from("<I", b, off)[0]; off += 4
    mg = struct.unpack_from("<I", b, off)[0]; off += 4
    de = struct.unpack_from("<I", b, off)[0]; off += 4
    rl = struct.unpack_from("<I", b, off)[0]; off += 4
    rev = b[off:off + rl].decode("ascii"); off += rl
    ts = {}
    for _ in range(nt):
        nl = struct.unpack_from("<I", b, off)[0]; off += 4
        nm = b[off:off + nl].decode("ascii"); off += nl
        dt = struct.unpack_from("<B", b, off)[0]; off += 1
        nd = struct.unpack_from("<B", b, off)[0]; off += 1
        shp = struct.unpack_from("<%dI" % nd, b, off); off += 4 * nd
        n = int(np.prod(shp))
        ts[nm] = np.frombuffer(b[off:off + 4 * n], dtype="float32").reshape(shp).copy()
        off += 4 * n
    return ts, rev


def run(prefix, target, D, B, K):
    full = list(prefix) + list(target)
    seq = list(prefix)
    blocks = []
    n_drafted = 0
    n_accepted = 0
    while len(seq) < len(full):
        draft = []
        tmp = list(seq)
        for _ in range(K):
            if len(tmp) >= 2:
                nxt = int(np.argmax(D[tmp[-2], tmp[-1]] + B))
                draft.append(nxt)
                tmp.append(nxt)
        n_drafted += len(draft)
        start = len(seq)
        acc = 0
        for j in range(len(draft)):
            pos = start + j
            if pos >= len(full):
                break
            if draft[j] == full[pos]:
                acc += 1
            else:
                break
        blocks.append({"start": start, "draft": draft, "accepted": acc,
                       "rejected": acc < len(draft) and (start + acc) < len(full)})
        for j in range(acc):
            seq.append(draft[j])
        n_accepted += acc
        if len(seq) < len(full):
            seq.append(full[len(seq)])
    return seq, n_drafted, n_accepted, blocks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prefix", default="2,4")
    ap.add_argument("--target", required=True)
    ap.add_argument("--draft", type=int, default=3)
    ap.add_argument("--out", default="/app/spec_out.json")
    args = ap.parse_args()

    ts, rev = load_tensors(args.model)
    prefix = [int(x) for x in args.prefix.split(",") if x != ""]
    target = [int(x) for x in args.target.split(",") if x != ""]
    if len(prefix) < 2:
        raise ValueError("prefix must be at least 2 token ids")
    if not target:
        raise ValueError("target must be non-empty")
    if args.draft < 1:
        raise ValueError("draft block length must be >= 1")

    out_seq, n_drafted, n_accepted, blocks = run(prefix, target, ts["D"], ts["B"], args.draft)

    result = {
        "ckpt": args.model,
        "revision": rev,
        "prefix": prefix,
        "target": target,
        "draft_len": args.draft,
        "result": out_seq,
        "n_drafted": n_drafted,
        "n_accepted": n_accepted,
        "n_verified": len(target) - n_accepted,
        "blocks": blocks,
    }
    with open(args.out, "w") as fh:
        json.dump(result, fh)
    print(json.dumps({"n_drafted": n_drafted, "n_accepted": n_accepted}))


if __name__ == "__main__":
    main()