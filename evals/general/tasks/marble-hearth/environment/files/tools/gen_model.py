#!/usr/bin/env python3
"""Deterministic tiny-GPT2 model-store generator for marble-hearth.

Usage: python3 gen_model.py <out_dir> <seed> <word_csv>
Builds a word-level tokenizer + a randomly initialized (seeded) tiny
GPT2 causal LM and saves both into <out_dir> (transformers format).
"""
import sys

import torch
from tokenizers import Tokenizer, models, pre_tokenizers
from transformers import GPT2Config, GPT2LMHeadModel, PreTrainedTokenizerFast


def main():
    out, seed, word_csv = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    words = [w for w in word_csv.split(",") if w]
    vocab = {"[UNK]": 0, "[PAD]": 1}
    for w in words:
        vocab[w] = len(vocab)
    tok = Tokenizer(models.WordLevel(vocab, unk_token="[UNK]"))
    tok.pre_tokenizer = pre_tokenizers.Whitespace()
    fast = PreTrainedTokenizerFast(tokenizer_object=tok, unk_token="[UNK]")

    torch.manual_seed(seed)
    cfg = GPT2Config(vocab_size=len(vocab), n_positions=64, n_embd=32,
                     n_layer=2, n_head=4, bos_token_id=None, eos_token_id=None)
    model = GPT2LMHeadModel(cfg)
    model.eval()

    fast.save_pretrained(out)
    model.save_pretrained(out, safe_serialization=True)
    print("generated", out)


if __name__ == "__main__":
    main()
