"""Deterministic synthetic classification data.

Class = (sum of all token ids in the sequence) modulo num_classes.
"""
import torch

from model import TConfig


def make_dataset(seed: int, n: int, cfg: TConfig):
    g = torch.Generator()
    g.manual_seed(seed)
    seqs = torch.randint(0, cfg.vocab_size, (n, cfg.max_len), generator=g)
    tgt = (seqs.sum(dim=1) % cfg.num_classes).long()
    return seqs, tgt