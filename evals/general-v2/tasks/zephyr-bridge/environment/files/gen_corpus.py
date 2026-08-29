"""gen_corpus.py -- deterministic synthetic two-class labeled text corpus.

The `zephyr` family ships a small synthetic "product verdict" corpus: every
line is ``label<TAB>text`` where a label is either ``neg`` or ``pos`` and the
text is a short review-like sentence built from a *class word pool* (a set of
pseudo-words unique to that class), shared filler words, and an anchor pair
(the first two tokens of every sentence) that co-occurs exclusively within its
own class.

The word pools are derived deterministically from ``--seed``, so a different
seed maps to an entirely different token universe (a genuinely fresh domain).
``--edge 1`` injects malformed / degenerate rows to probe robustness:
   * fully blank lines,
   * punctuation-only rows (no word tokens),
   * digit-only rows,
   * very short (single token) rows,
   * duplicate rows, and
   * rows with a missing TAB separator (dropped by the loader).

Usage:
    python3 gen_corpus.py --out FILE [--seed N] [--count N] [--edge 0|1]

The fixture is generated at image build time for the shipped corpus; the
verifier (and hidden runs) reuse this exact generator with other seeds.
"""

import argparse
import os
import random


ALPHA = "bcdfghjklmnpqrstvwxz"


def word(rng: random.Random, mn=5, mx=9) -> str:
    w = []
    for _ in range(rng.randint(mn, mx)):
        w.append(rng.choice(ALPHA))
    return "".join(w)


def pool(rng: random.Random, n: int) -> list:
    s = set()
    while len(s) < n:
        s.add(word(rng))
    return sorted(s)


def sent(rng: random.Random, anchors: str, class_pool, shared) -> str:
    n = rng.randint(5, 9)
    picked = rng.sample(class_pool, min(n, len(class_pool)))
    shared_toks = rng.sample(shared, rng.randint(1, 3))
    text = " ".join(picked + shared_toks)
    text = anchors + " " + text
    r = rng.random()
    if r < 0.6:
        text += rng.choice([",", "!", ".", ",!", "?!", ";"])
    return text


def build(seed: int, count: int, edge: bool):
    rng = random.Random(seed)
    pos_pool = pool(rng, 700)
    neg_pool = pool(rng, 700)
    shared = pool(rng, 300)
    pA, pB = word(rng), word(rng)
    nA, nB = word(rng), word(rng)
    pos_anchor = "%s %s" % (pA, pB)
    neg_anchor = "%s %s" % (nA, nB)

    rows = []
    half = count // 2
    for _ in range(half):
        rows.append(("pos", sent(rng, pos_anchor, pos_pool, shared)))
    for _ in range(count - half):
        rows.append(("neg", sent(rng, neg_anchor, neg_pool, shared)))

    if edge:
        extras = []
        for _ in range(int(count * 0.06)):
            extras.append(("pos", ""))
        for _ in range(int(count * 0.06)):
            extras.append(("neg", "!!?!,.;:"))
        for _ in range(int(count * 0.06)):
            extras.append(("pos", "3847291 556"))
        for _ in range(int(count * 0.06)):
            extras.append(("neg", pA))
        # rows with a missing TAB separator are dropped by the loader
        for _ in range(int(count * 0.06)):
            extras.append(("pos", "no tab line here"))
        rows.extend(extras)

    rng2 = random.Random(seed ^ 0x5A5A)
    rng2.shuffle(rows)
    return rows, (pA, pB, nA, nB)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/app/data/reviews.tsv")
    ap.add_argument("--seed", type=int, default=777)
    ap.add_argument("--count", type=int, default=2400)
    ap.add_argument("--edge", type=int, default=0)
    args = ap.parse_args()

    rows, anchors = build(args.seed, args.count, bool(args.edge))
    import os
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        for lab, text in rows:
            fh.write("%s\t%s\n" % (lab, text))
        if args.edge:
            # raw rows with no TAB separator must be skipped by the loader
            for _ in range(int(args.count * 0.05)):
                fh.write("loose token stream with no separator\n")
    print("wrote %d rows -> %s (anchors=%s)" % (len(rows), args.out, anchors))


if __name__ == "__main__":
    main()