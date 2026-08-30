#!/usr/bin/env python3
"""Train a byte-pair-encoding tokenizer to a bounded vocabulary.

A single run is fully deterministic: the training data, BPE algorithm and
merge tie-breaking all come from the `tokenizers` library, so running the tool
twice on the same corpus yields byte-identical artifacts and identical
encodings. Produces a persisted model at `--out` (a JSON dump that can be
reloaded with `Tokenizer.from_file`).
"""
import argparse

from tokenizers import Tokenizer
from tokenizers.decoders import ByteLevel
from tokenizers.models import BPE
from tokenizers.pre_tokenizers import ByteLevel as ByteLevelPre
from tokenizers.trainers import BpeTrainer


def main() -> int:
    ap = argparse.ArgumentParser(description="train a bounded BPE tokenizer")
    ap.add_argument("--corpus", required=True, help="training corpus (text file)")
    ap.add_argument("--out", required=True, help="output tokenizer model path")
    ap.add_argument("--vocab-size", type=int, default=512,
                    help="upper bound on vocabulary size")
    ap.add_argument("--min-frequency", type=int, default=1,
                    help="minimum n-gram frequency")
    args = ap.parse_args()

    tokenizer = Tokenizer(BPE(unk_token="<unk>"))
    tokenizer.pre_tokenizer = ByteLevelPre(add_prefix_space=False)
    tokenizer.decoder = ByteLevel()

    trainer = BpeTrainer(
        vocab_size=args.vocab_size,
        min_frequency=args.min_frequency,
        special_tokens=["<unk>"],
    )

    with open(args.corpus, "r", encoding="utf-8", errors="replace") as fh:
        lines = [ln for ln in fh]

    if lines:
        tokenizer.train_from_iterator(lines, trainer=trainer)

    tokenizer.save(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())