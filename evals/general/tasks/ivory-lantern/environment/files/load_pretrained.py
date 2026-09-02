#!/usr/bin/env python3
"""Offline pretrained-asset loader for the ivory-lantern kiosk.

This loader runs with the network off. It inspects a local assets directory
for the COMPLETE set of artifacts a pretrained load requires:

    config.json            model architecture metadata
    weights.npz            2-D float32 weight shards (numpy .npz)
    vocab.json             token -> id map
    merges.txt             whitespace-separated BPE merge pairs
    tokenizer_config.json  tokenizer settings
    special_tokens_map.json special token roles

If ANY of the six is absent the load MUST fail (that is the whole point of a
complete-mirror requirement) — a partial mirror is not servable offline.

Do not modify this file; the deployment image ships it read-only.
"""
import json
import os
import sys

import numpy as np

REQUIRED = [
    "config.json",
    "weights.npz",
    "vocab.json",
    "merges.txt",
    "tokenizer_config.json",
    "special_tokens_map.json",
]


def _force_offline():
    # HF-style offline switches: nothing may reach for the network.
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_OFFLINE"] = "1"


class KioskTokenizer:
    """Whitespace token -> id with an <unk> fallback."""

    def __init__(self, vocab, merges, special):
        self.vocab = dict(vocab)
        self.merges = [tuple(pair) for pair in merges]
        self.special_tokens_map = dict(special)

    def encode(self, text):
        unk = self.special_tokens_map.get("unk_token")
        ids = []
        for tok in str(text).split():
            if tok in self.vocab:
                ids.append(self.vocab[tok])
            elif unk is not None and unk in self.vocab:
                ids.append(self.vocab[unk])
            else:
                raise KeyError("no id for token %r and no usable unk" % tok)
        return ids

    def decode(self, ids):
        inv = {v: k for k, v in self.vocab.items()}
        return " ".join(inv[int(i)] for i in ids)


def load_pretrained(assets_dir):
    _force_offline()
    assets_dir = str(assets_dir)
    missing = [f for f in REQUIRED
               if not os.path.isfile(os.path.join(assets_dir, f))]
    if missing:
        raise FileNotFoundError(
            "offline assets incomplete at %r; missing: %s" % (assets_dir, missing))

    with open(os.path.join(assets_dir, "config.json")) as fh:
        config = json.load(fh)
    with open(os.path.join(assets_dir, "tokenizer_config.json")) as fh:
        tokenizer_config = json.load(fh)
    with open(os.path.join(assets_dir, "special_tokens_map.json")) as fh:
        special = json.load(fh)
    with open(os.path.join(assets_dir, "vocab.json")) as fh:
        vocab = json.load(fh)

    merges = []
    with open(os.path.join(assets_dir, "merges.txt")) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 2:
                raise ValueError("bad merge line: %r" % line)
            merges.append(parts)

    with np.load(os.path.join(assets_dir, "weights.npz")) as z:
        weights = {k: np.asarray(z[k], dtype=np.float32) for k in z.files}
    for k, v in weights.items():
        if v.ndim != 2:
            raise ValueError("weight %r is not 2-D (got shape %s)" % (k, v.shape))

    tokenizer = KioskTokenizer(vocab, merges, special)
    return {
        "config": config,
        "tokenizer": tokenizer,
        "tokenizer_config": tokenizer_config,
        "special_tokens_map": special,
        "weights": weights,
    }


def main(argv):
    _force_offline()
    if len(argv) != 2:
        print("usage: load_pretrained.py <assets_dir>", file=sys.stderr)
        return 2
    try:
        bundle = load_pretrained(argv[1])
    except Exception as exc:
        print("OFFLINE_LOAD_FAILED: %s" % exc)
        return 1
    n_w = len(bundle["weights"])
    n_v = len(bundle["tokenizer"].vocab)
    print("OFFLINE_LOAD_OK %s weights=%d vocab=%d" % (argv[1], n_w, n_v))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
