#!/usr/bin/env python3
"""Generates a tiny GPT2-style LM + fast word-level tokenizer repo for the
ember-atlas hub. Deterministic given (seed, words)."""
import json
import os
import sys

import torch
from tokenizers import Tokenizer, models, pre_tokenizers
from transformers import GPT2Config, GPT2LMHeadModel, PreTrainedTokenizerFast

WORDS = [
    "<unk>", "the", "ridge", "topoline", "sweep", "cairn", "aurora", "basin",
    "col", "tarn", "scree", "fell", "boulder", "gully", "arête", "hollow",
    "summit", "traverse", "ledge", "mantle", "crux", "belay", "rime",
    "cornice", "moraine", "tarn", "cirque", "horn", "col", "pyramid",
    "spire", "tarn", "of", "and", "in", "on", "at", "to", "a",
]


def make_repo(outdir, seed, extra_words):
    os.makedirs(outdir, exist_ok=True)
    words = ["<unk>"] + [w for w in dict.fromkeys(
        (extra_words + WORDS[1:])) if w != "<unk>"]
    vocab = {w: i for i, w in enumerate(words)}
    tk_model = models.WordLevel(vocab, unk_token="<unk>")
    tok = Tokenizer(tk_model)
    tok.pre_tokenizer = pre_tokenizers.Whitespace()
    fast = PreTrainedTokenizerFast(
        tokenizer_object=tok, unk_token="<unk>", pad_token="<unk>")
    fast.save_pretrained(outdir)

    torch.manual_seed(seed)
    config = GPT2Config(
        vocab_size=len(vocab), n_positions=32, n_ctx=32, n_embd=24,
        n_layer=1, n_head=3, bos_token_id=0, eos_token_id=0)
    model = GPT2LMHeadModel(config)
    model.save_pretrained(outdir)
    files = sorted(os.listdir(outdir))
    print(json.dumps({"dir": outdir, "files": files}))


if __name__ == "__main__":
    make_repo(sys.argv[1], int(sys.argv[2]), sys.argv[3].split(","))
