"""Meridian text embedder (shipped model code -- DO NOT MODIFY).

Deterministic hashed-character-trigram embedder pinned to a model revision.
The embedding of a text depends ONLY on the shipped projection matrix in the
weights file, so two revisions with different weights produce genuinely
different embeddings (and can produce different similarity orderings).

Usage:
    import model  # the copy inside the model_dir given by the manifest
    proj, revision = model.load_weights(weights_path)
    vecs = model.embed_texts(texts, proj)   # (N, 32) float64, L2-normalised

Algorithm (normative):
  1. normalise text: lowercase, collapse every whitespace run to a single
     space, strip, then pad with one leading and one trailing space.
  2. take all char trigrams of the padded string.
  3. for trigram g: bucket d = blake2b(g, digest_size=8, little-endian u64)
     mod 256; sign = +1 if the first byte of blake2b(g + "#", digest_size=8)
     is odd, else -1; add sign to h[d].
  4. L2-normalise h; project e = h @ proj (shape (256, 32)); L2-normalise e.
"""
import hashlib

import numpy as np

D = 256


def norm_text(t):
    return " " + " ".join(str(t).lower().split()) + " "


def hvec(text):
    s = norm_text(text)
    h = np.zeros(D, dtype=np.float64)
    for i in range(len(s) - 2):
        g = s[i:i + 3]
        d = int.from_bytes(
            hashlib.blake2b(g.encode("utf-8"), digest_size=8).digest(),
            "little") % D
        sign = 1.0 if hashlib.blake2b((g + "#").encode("utf-8"),
                                      digest_size=8).digest()[0] & 1 else -1.0
        h[d] += sign
    n = float(np.sqrt((h * h).sum()))
    if n > 0:
        h /= n
    return h


def load_weights(path):
    z = np.load(path)
    return z["proj"].astype(np.float64), str(z["revision"])


def embed_texts(texts, proj):
    E = np.stack([hvec(t) @ proj for t in texts])
    n = np.sqrt((E * E).sum(axis=1, keepdims=True))
    n[n == 0.0] = 1.0
    return E / n
