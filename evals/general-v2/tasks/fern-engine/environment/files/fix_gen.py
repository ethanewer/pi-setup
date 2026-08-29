#!/usr/bin/env python3
"""Generates all fern-engine fixtures at Docker build time.

Writes VISIBLE fixtures under /app/ and HIDDEN verifier fixtures under
/buildout/hidden (later `docker cp`'d to tests/hidden on the host). Seeded so
every build is reproducible.
"""
import csv
import json
import os

import torch
from torch import nn
from transformers import GPT2Config, GPT2LMHeadModel, BertTokenizer

APP = "/app"
BUILDOUT = "/buildout/hidden"


def make_lm(outpath, letters, seed):
    os.makedirs(outpath, exist_ok=True)
    tokenizer = _gpt_tokenizer(outpath, letters)
    vocab_size = len(tokenizer)
    torch.manual_seed(seed)
    config = GPT2Config(
        vocab_size=vocab_size,
        n_positions=64,
        n_ctx=64,
        n_embd=24,
        n_layer=1,
        n_head=2,
        eos_token_id=0,
        pad_token_id=0,
        bos_token_id=0,
        resid_pdrop=0.0,
        embd_pdrop=0.0,
        attn_pdrop=0.0,
        output_attentions=False,
        output_hidden_states=False,
    )
    model = GPT2LMHeadModel(config)
    model.save_pretrained(outpath)
    tokenizer.save_pretrained(outpath)


def _gpt_tokenizer(outpath, letters):
    vocab = ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]"] + list(letters)
    with open(os.path.join(outpath, "vocab.txt"), "w") as fh:
        fh.write("\n".join(vocab) + "\n")
    with open(os.path.join(outpath, "tokenizer_config.json"), "w") as fh:
        json.dump({"tokenizer_class": "BertTokenizer"}, fh)
    return BertTokenizer.from_pretrained(outpath)


def _build_clf(in_f, hidden, k, seed):
    torch.manual_seed(seed)
    m = nn.Sequential()
    m.encoder = nn.Linear(in_f, hidden)
    m.act = nn.Tanh()
    m.head = nn.Linear(hidden, k)
    return m


def save_clf(outpath, in_f, hidden, k, seed):
    m = _build_clf(in_f, hidden, k, seed)
    os.makedirs(outpath, exist_ok=True)
    with open(os.path.join(outpath, "config.json"), "w") as fh:
        json.dump({"in_features": in_f, "hidden_size": hidden, "num_labels": k}, fh)
    torch.save(m.state_dict(), os.path.join(outpath, "state.pt"))


def save_state_dict(pkl, in_f, hidden, k, seed):
    torch.manual_seed(seed)
    m = _build_clf(in_f, hidden, k, seed)
    torch.save(m.state_dict(), pkl)


def write_train_set(dirpath, hdr, rows, evalrows):
    os.makedirs(dirpath, exist_ok=True)
    with open(os.path.join(dirpath, "train.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(hdr + ["label"])
        for r in rows:
            w.writerow(r)
    with open(os.path.join(dirpath, "eval.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(hdr)
        for r in evalrows:
            w.writerow(r)


def main():
    # ----------------------- visible fixtures under /app -----------------------
    make_lm(os.path.join(APP, "pretrained_lm"), "abcdefghijklmnopqrstuvwxyz", seed=11)

    os.makedirs(APP, exist_ok=True)
    save_state_dict(os.path.join(APP, "state_seed.pkl"), in_f=5, hidden=6, k=3, seed=42)
    save_clf(os.path.join(APP, "base_clf"), in_f=6, hidden=8, k=2, seed=111)

    write_train_set(
        os.path.join(APP, "data"),
        ["f1", "f2", "f3"],
        [
            [1.0, 0.0, 0.0, 0],
            [0.0, 1.0, 0.0, 0],
            [0.0, 0.0, 1.0, 1],
            [1.0, 1.0, 0.0, 1],
            [-1.0, 0.0, 1.0, 1],
            [0.5, 0.5, 0.0, 0],
            [-0.5, 1.0, 0.5, 2],
            [0.0, -0.5, 1.0, 2],
        ],
        [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 0.5, 0.5]],
    )

    with open(os.path.join(APP, "base_eval.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["b1", "b2", "b3", "b4", "b5", "b6"])
        w.writerow([0.5, -0.2, 0.1, 0.0, 0.3, 1.0])
        w.writerow([-1.0, 0.0, 0.5, 0.2, 0.0, -0.4])

    # ----------------------- hidden fixtures --------------------------------
    hidden = BUILDOUT

    make_lm(os.path.join(hidden, "h_offline", "model"), "abcdefghikmoqrstuwy", seed=505)
    with open(os.path.join(hidden, "h_offline", "prompt.txt"), "w") as fh:
        fh.write("quill dell")

    hreb = os.path.join(hidden, "h_rebuild")
    os.makedirs(hreb, exist_ok=True)
    save_state_dict(os.path.join(hreb, "state.pkl"), in_f=4, hidden=5, k=2, seed=7)
    with open(os.path.join(hreb, "expected.json"), "w") as fh:
        json.dump({"in_features": 4, "hidden_size": 5, "num_labels": 3}, fh)

    hrec = os.path.join(hidden, "h_reconfig")
    save_clf(os.path.join(hrec, "base"), in_f=4, hidden=6, k=3, seed=99)
    with open(os.path.join(hrec, "K.txt"), "w") as fh:
        fh.write("7")
    with open(os.path.join(hrec, "eval.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["c1", "c2", "c3", "c4"])
        w.writerow([0.5, 0.1, 0.2, 0.0])
        w.writerow([-1.0, 1.0, 0.0, 0.5])

    htr = os.path.join(hidden, "h_train", "data")
    write_train_set(
        htr,
        ["p1", "p2"],
        [
            [0.0, 0.0, 0],
            [1.0, 0.0, 1],
            [0.0, 1.0, 1],
            [1.0, 1.0, 2],
            [-1.0, 0.0, 1],
            [0.0, -1.0, 2],
        ],
        [[0.5, 0.0], [1.0, 1.0], [-1.0, 0.5]],
    )

    bad = os.path.join(hidden, "errors")
    os.makedirs(os.path.join(bad, "e1_rebuild_bad"), exist_ok=True)
    with open(os.path.join(bad, "e1_rebuild_bad", "thing.bin"), "w") as fh:
        fh.write("not a torch state dict at all\n")
    os.makedirs(os.path.join(bad, "e2_train_empty"), exist_ok=True)
    with open(os.path.join(bad, "e2_train_empty", "train.csv"), "w") as fh:
        fh.write("f1,f2,label\n")

    print("fix_gen: visible fixtures under %s, hidden under %s" % (APP, BUILDOUT))


if __name__ == "__main__":
    main()