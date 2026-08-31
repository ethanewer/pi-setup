"""gen_tickets.py -- deterministic 4-class support-ticket corpus for iris-crate.

The Relayline depot helpdesk triages inbound tickets into four queues:
BILLING, DAMAGES, RETURNS, TRACKING.  Every row is ``label<TAB>text``.

Each ticket is built from a class word pool (depot-specific vocabulary),
shared filler words, a numeric order id, and one *confuser* word borrowed
from another class, so a bag-of-n-grams model must combine several weak
signals.  ``--edge 1`` injects malformed / degenerate rows that a robust
trainer must skip:
  * fully blank lines,
  * rows with no TAB separator,
  * rows with an empty label or empty text,
  * punctuation-only rows.

Usage:
    python3 gen_tickets.py --train T.tsv --holdout H.tsv \
        [--seed N] [--count N] [--holdout-count M] [--edge 0|1]
"""

import argparse
import os
import random

LABELS = ["BILLING", "DAMAGES", "RETURNS", "TRACKING"]

POOL = {
    "BILLING": ("invoice refund charge card subscription billed receipt "
                "payment overcharge statement credit prorated").split(),
    "DAMAGES": ("crushed broken leaking smashed torn dented soaked shattered "
                "split bent waterlogged mangled").split(),
    "RETURNS": ("return exchange rma swap restock resell replacement "
                "sendback unworn reship").split(),
    "TRACKING": ("tracking package parcel delayed warehouse scan transit "
                 "carrier depot route customs manifest").split(),
}

FILLER = ("the my a this order please still again today thanks hello team "
          "help quick note update asap week morning arrival status account "
          "number since").split()

CONFUSERS = {
    "BILLING": "package box label address shipment".split(),
    "TRACKING": "refund invoice box cost charge".split(),
    "DAMAGES": "refund box return packaging courier".split(),
    "RETURNS": "package tracking box pickup courier".split(),
}

NOUNS = "order shipment ticket consignment parcel delivery".split()

PUNCT = ["!", "!!", "?", "??", "...", " .", " - please advise", ","]


def make_text(rng: random.Random, label: str) -> str:
    pool = POOL[label]
    cws = rng.sample(pool, rng.randint(2, 3))
    # confuser words borrowed from other classes' pools
    others = [l for l in LABELS if l != label]
    conf = " ".join(rng.choice(POOL[rng.choice(others)])
                    for _ in range(rng.randint(1, 2)))
    fill1 = " ".join(rng.sample(FILLER, rng.randint(2, 4)))
    fill2 = " ".join(rng.sample(FILLER, rng.randint(1, 3)))
    noun = rng.choice(NOUNS)
    num = str(rng.randint(10000, 99999))
    parts = [fill1, noun, num] + cws + [conf, fill2]
    text = " ".join(p for p in parts if p)
    roll = rng.random()
    if roll < 0.12:
        text = text.upper()
    elif roll < 0.24:
        text = text.capitalize()
    text += rng.choice(PUNCT)
    return text


def emit(f, rng: random.Random, n: int, edge: bool, labels: list) -> int:
    written = 0
    for _ in range(n):
        label = rng.choice(labels)
        text = make_text(rng, label)
        if edge and rng.random() < 0.10:
            roll = rng.random()
            if roll < 0.25:
                f.write("\n")                       # blank line
                continue
            if roll < 0.5:
                f.write(text.replace("\t", " ") + "\n")   # no TAB
                continue
            if roll < 0.75:
                f.write(label + "\t   \n")          # empty text
                continue
            f.write(label + "\t!!! ... ???\n")      # punctuation-only
            continue
        f.write("%s\t%s\n" % (label, text))
        written += 1
    return written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True)
    ap.add_argument("--holdout", required=True)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--count", type=int, default=4000)
    ap.add_argument("--holdout-count", type=int, default=1000)
    ap.add_argument("--edge", type=int, default=0)
    args = ap.parse_args()

    for path in (args.train, args.holdout):
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)

    # disjoint RNG streams: train and holdout never share generated rows
    rng_tr = random.Random(args.seed * 1000003 + 1)
    rng_ho = random.Random(args.seed * 1000003 + 2)
    n_tr = emit(open(args.train, "w", encoding="utf-8"),
                rng_tr, args.count, bool(args.edge), LABELS)
    n_ho = emit(open(args.holdout, "w", encoding="utf-8"),
                rng_ho, args.holdout_count, bool(args.edge), LABELS)
    print("train rows=%d holdout rows=%d" % (n_tr, n_ho))


if __name__ == "__main__":
    main()
