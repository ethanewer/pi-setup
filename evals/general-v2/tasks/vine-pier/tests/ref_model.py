"""tests/ref_model.py -- the verifier's independent reference implementation.

Implements the same checkpoint/vocab parsing, greedy generation, speculative
draft-and-verify loop and revision-pinned cosine retrieval that the worker
programs must produce, so the verifier can recompute expected values from fresh
inputs and compare them byte-for-byte against the agent's deliverables. Held
under tests/ and only invoked by test.sh (never mounted into /app for the
agent). Independently re-implemented from instruction.md -- deliberately not
shared code with /app.
"""
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
    tensors = {}
    order = []
    for _ in range(nt):
        nl = struct.unpack_from("<I", b, o)[0]; o += 4
        nm = b[o:o + nl].decode("ascii"); o += nl
        dt = struct.unpack_from("<B", b, o)[0]; o += 1
        nd = struct.unpack_from("<B", b, o)[0]; o += 1
        shp = struct.unpack_from("<%dI" % nd, b, o); o += 4 * nd
        n = int(np.prod(shp))
        arr = np.frombuffer(b[o:o + 4 * n], dtype="float32").reshape(shp).copy()
        o += 4 * n
        tensors[nm] = arr
        order.append((nm, dt, shp, arr))
    return {"V": V, "nT": nt, "max_gen": mg, "d_emb": de,
            "rev": rev, "tensors": tensors, "order": order}


def greedy(prompt, W, B, count):
    seq = list(prompt)
    base = W + B[None, None, :]
    for _ in range(count):
        seq.append(int(np.argmax(base[seq[-2], seq[-1]])))
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
    return seq, {"blocks": blocks, "n_drafted": n_drafted, "n_accepted": n_accepted}


def embed_row(emb, ids):
    if not ids:
        v = np.zeros(emb.shape[1], dtype="float64")
    else:
        v = emb[np.asarray(ids)].sum(axis=0).astype("float64")
    n = np.linalg.norm(v)
    return v if n == 0 else v / n


def pretrieve(emb, docs, query):
    qv = embed_row(emb, query)
    scored = []
    for i, dids in enumerate(docs):
        dv = embed_row(emb, dids)
        cos = float(np.dot(dv, qv)) if (np.linalg.norm(dv) and np.linalg.norm(qv)) else 0.0
        scored.append((i, cos))
    scored.sort(key=lambda t: (-t[1], t[0]))
    return scored

def fnv1a64(data):
    h = 14695981039346656037
    p = 1099511628211
    for byte in data:
        h = (h ^ byte) * p & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h


def load_vocab(path, V):
    voc = {}
    for line in open(path):
        line = line.rstrip("\n")
        if not line:
            continue
        a, _, btok = line.partition("\t")
        voc[int(a)] = btok
    if len(voc) != V:
        raise ValueError("vocab size %d != %d" % (len(voc), V))
    return voc


def reader_dump(ckpt_path, vocab_path):
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
