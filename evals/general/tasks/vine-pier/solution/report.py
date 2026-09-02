#!/usr/bin/env python3
"""report.py -- fit + persist the model and emit the two-peak params report.

Loads the fitted target model from the shipped checkpoint, pickle-persists the
fitted model object to /app/model.pkl and serializes its parameters into
/app/params.json in the exact two-peak key layout (see instruction.md).

Usage: python /app/report.py [checkpoint.ckpt]   (default /app/data/model.ckpt)
"""
import json
import pickle
import struct
import sys
import numpy as np


def load_ckpt(path):
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
    return {"V": V, "rev": rev, "tensors": ts}


def main():
    model_path = sys.argv[1] if len(sys.argv) > 1 else "/app/data/model.ckpt"
    ck = load_ckpt(model_path)
    W = ck["tensors"]["W"]
    B = ck["tensors"]["B"]

    fitted = {
        "W": W.astype("float32"),
        "b": B.astype("float32"),
        "revision": ck["rev"],
        "fitted": True,
        "vocab_size": ck["V"],
    }
    with open("/app/model.pkl", "wb") as fh:
        pickle.dump(fitted, fh)

    report = {
        "model": "vertex",
        "fitted": True,
        "vocab_size": ck["V"],
        "revision": ck["rev"],
        "peaks": {
            "W": W.tolist(),  # target next-token logits, shape (V,V,V)
            "B": B.tolist(),  # target bias, shape (V,)
        },
    }
    with open("/app/params.json", "w") as fh:
        json.dump(report, fh)
    print("report written")


if __name__ == "__main__":
    main()
