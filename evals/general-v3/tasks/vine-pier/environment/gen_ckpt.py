import os
#!/usr/bin/env python3
import os
"""vine-pier fixture generator + model loader / arithmetic (shared by tools).
import os

import os
This generator produces a small custom serialized transformer checkpoint plus a
import os
byte-pair vocabulary, and the loader/model arithmetic used by the reference
import os
reader and the solution programs. The binary format is documented in
import os
instruction.md.
import os
"""
import os
import struct
import os
import sys
import numpy as np

MAGIC = b"VINER1"


def fnv1a64(data):
    h = 14695981039346656037
    p = 1099511628211
    for byte in data:
        h = (h ^ byte) * p & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h


def make_ckpt(path, V, d_emb, max_gen, rev, seed, tensor_names):
    rng = np.random.default_rng(seed)
    W = rng.normal(0.0, 1.0, (V, V, V)).astype("float32")
    B = rng.normal(0.0, 0.1, (V,)).astype("float32")
    D = rng.uniform(-1.0, 1.0, (V, V, V)).astype("float32")
    emb = rng.normal(0.0, 0.3, (V, 8)).astype("float32")
    table = {"W": W, "B": B, "D": D, "emb": emb}
    out = bytearray()
    out += MAGIC
    out += b"\x00\x00"
    out += struct.pack("<I", V)             # vocab_size      [8:12]
    out += struct.pack("<I", len(tensor_names))  # n_tensors [12:16]
    out += struct.pack("<I", max_gen)        # max_gen         [16:20]
    out += struct.pack("<I", 8)             # d_emb            [20:24]
    rev = rev.encode("ascii")
    out += struct.pack("<I", len(rev))
    out += rev
    for name in tensor_names:
        arr = table[name]
        nb = name.encode("ascii")
        out += struct.pack("<I", len(nb))
        out += nb
        out += struct.pack("<B", 0)          # dtype 0 = float32
        out += struct.pack("<B", arr.ndim)   # ndim
        for sh in arr.shape:
            out += struct.pack("<I", sh)
        out += arr.tobytes()
    with open(path, "wb") as fh:
        fh.write(bytes(out))
    return table


def load_ckpt(path):
    b = open(path, "rb").read()
    o = 0
    assert b[o:o + 6] == MAGIC, b[o:o + 6]
    o = 8
    V = struct.unpack_from("<I", b, o)[0]; o += 4
    nt = struct.unpack_from("<I", b, o)[0]; o += 4
    mg = struct.unpack_from("<I", b, o)[0]; o += 4
    de = struct.unpack_from("<I", b, o)[0]; o += 4
    rl = struct.unpack_from("<I", b, o)[0]; o += 4
    rev = b[o:o + rl].decode("ascii"); o += rl
    tensors = {}
    order = []
    for _ in range(nt):
        nl = struct.unpack_from("<I", b, o)[0]; o += 4
        nm = b[o:o + nl].decode("ascii"); o += nl
        dt = struct.unpack_from("<B", b, o)[0]; o += 1
        nd = struct.unpack_from("<B", b, o)[0]; o += 1
        shp = struct.unpack_from("<%dI" % nd, b, o); o += 4 * nd
        n = int(np.prod(shp))
        raw = b[o:o + 4 * n]; o += 4 * n
        arr = np.frombuffer(raw, dtype="float32").reshape(shp).copy()
        tensors[nm] = arr
        order.append((nm, dt, shp, arr))
    return {"V": V, "nT": nt, "max_gen": mg, "d_emb": de,
            "rev": rev, "tensors": tensors, "order": order}


def load_vocab(path, V):
    """vocab text: one line per id 'id<TAB>token'. Returns dict id->token."""
    voc = {}
    with open(path, "r") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            pos = line.index("\t")
            voc[int(line[:pos])] = line[pos + 1:]
    if len(voc) != V:
        raise ValueError("vocab size mismatch: got %d want %d" % (len(voc), V))
    return voc


def reader_dump(ckpt_path, vocab_path):
    """Reference dump produced by the pure-C reader; the tests compare the C
    stdout byte-for-byte to these lines."""
    ck = load_ckpt(ckpt_path)
    lines = []
    lines.append("REV %s" % ck["rev"].encode().hex())
    lines.append("VSIZE %d" % ck["V"])
    lines.append("MAXGEN %d" % ck["max_gen"])
    for name, dt, shp, arr in ck["order"]:
        lines.append("CKPT %s dtype=%d ndim=%d [%s] nelems=%d fn=%s" % (
            name, dt, len(shp), " ".join(str(s) for s in shp), arr.size,
            fnv1a64(arr.tobytes())))
    lines.append("---")
    voc = load_vocab(vocab_path, ck["V"])
    for ident in range(ck["V"]):
        lines.append("TOK %d %s" % (ident, voc[ident]))
    return lines


def argmax_next(W, B, a, b):
    """argmax over the last axis with ties broken toward the lowest index."""
    return int(np.argmax(W[a, b] + B))


def greedy(prompt, W, B, max_gen):
    seq = list(prompt)
    for _ in range(max_gen):
        seq.append(argmax_next(W, B, seq[-2], seq[-1]))
    return seq


def run_spec(prefix, target, D, B, K):
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


def embed_doc(emb, ids):
    if not ids:
        v = np.zeros(emb.shape[1], dtype="float64")
    else:
        v = emb[np.asarray(ids)].sum(axis=0).astype("float64")
    n = np.linalg.norm(v)
    return v if n == 0 else v / n


def retrieve(emb, docs, query):
    qv = embed_doc(emb, query)
    scored = []
    for i, dids in enumerate(docs):
        dv = embed_doc(emb, dids)
        cos = float(np.dot(dv, qv)) if (np.linalg.norm(dv) and np.linalg.norm(qv)) else 0.0
        scored.append((i, dids, cos))
    # sort by cosine desc, then by doc index asc
    scored.sort(key=lambda t: (-t[2]), )
    scored.sort(key=lambda t: (-t[2], t[0]))
    rank = []
    for p, (i, dids, cos) in enumerate(scored, start=1):
        rank.append({"doc": i, "position": p, "cosine": round(cos, 6)})
    return rank


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "make":
        make_ckpt(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]),
                  int(sys.argv[5]), sys.argv[6], None,
                  sys.argv[7].split(","))