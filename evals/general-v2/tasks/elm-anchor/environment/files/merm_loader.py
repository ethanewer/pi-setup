"""Merm tokenizer loader (shipped -- DO NOT MODIFY).

This module defines the ONLY accepted on-disk conventions for the vocabulary
and merge-rule files, and the reference BPE encode/decode built on them.

Vocabulary file (`vocab.txt`):
    one token per line, UTF-8; line N (0-based) is token index N.
    A line that is blank, has leading/trailing whitespace, contains internal
    whitespace, or duplicates an earlier token makes loading FAIL.

Merge file (`merges.txt`):
    one merge rule per line: two whitespace-free symbols separated by a single
    space, e.g. `th e`.  Line order is priority (line 0 is applied first).
    Loading FAILS unless, for every line i: both symbols are either a single
    character or a merged token introduced by an EARLIER line, and the merged
    token a+b is present in the vocabulary.  A rule that references a merge
    introduced LATER breaks the chain and makes loading FAIL.

Usage:
    import merm_loader as ml
    tok = ml.MermTokenizer("vocab.txt", "merges.txt")
    ids = tok.encode("some text")      # list of ints
    text = tok.decode(ids)
"""


def load_vocab(path):
    tokens = []
    seen = set()
    with open(path, "r", encoding="utf-8") as fh:
        for i, raw in enumerate(fh):
            line = raw.rstrip("\n")
            if line == "":
                raise ValueError("vocab line %d is blank" % (i + 1))
            if line.split() != [line]:
                raise ValueError("vocab line %d has stray whitespace" % (i + 1))
            if line in seen:
                raise ValueError("vocab line %d duplicates %r" % (i + 1, line))
            seen.add(line)
            tokens.append(line)
    if not tokens:
        raise ValueError("vocab is empty")
    return tokens


def load_merges(path, vocab):
    vocab_set = set(vocab)
    introduced = set()
    ranks = {}
    with open(path, "r", encoding="utf-8") as fh:
        for i, raw in enumerate(fh):
            line = raw.rstrip("\n")
            if line == "":
                raise ValueError("merges line %d is blank" % (i + 1))
            parts = line.split(" ")
            if len(parts) != 2 or not parts[0] or not parts[1]:
                raise ValueError("merges line %d is malformed" % (i + 1))
            a, b = parts
            for s in (a, b):
                if s not in vocab_set:
                    raise ValueError(
                        "merges line %d: symbol %r not in vocab" % (i + 1, s))
                if len(s) != 1 and s not in introduced:
                    raise ValueError(
                        "merges line %d: symbol %r not introduced by an "
                        "earlier rule (chain broken/misordered)" % (i + 1, s))
            merged = a + b
            if merged not in vocab_set:
                raise ValueError(
                    "merges line %d: merged token %r not in vocab" % (i + 1, merged))
            ranks[(a, b)] = len(ranks)
            introduced.add(merged)
    return ranks


class MermTokenizer:
    def __init__(self, vocab_path, merges_path):
        self.tokens = load_vocab(vocab_path)
        self.ranks = load_merges(merges_path, self.tokens)
        self.index = {t: i for i, t in enumerate(self.tokens)}

    def encode_word(self, word):
        syms = list(word)
        while len(syms) > 1:
            best_rank = None
            best_pair = None
            for i in range(len(syms) - 1):
                r = self.ranks.get((syms[i], syms[i + 1]))
                if r is not None and (best_rank is None or r < best_rank):
                    best_rank = r
                    best_pair = (syms[i], syms[i + 1])
            if best_pair is None:
                break
            a, b = best_pair
            merged = a + b
            out = []
            i = 0
            while i < len(syms):
                if i < len(syms) - 1 and syms[i] == a and syms[i + 1] == b:
                    out.append(merged)
                    i += 2
                else:
                    out.append(syms[i])
                    i += 1
            syms = out
        return [self.index[s] for s in syms]

    def encode(self, text):
        ids = []
        for word in text.split():
            ids.extend(self.encode_word(word))
        return ids

    def decode(self, ids):
        return " ".join(self.tokens[i] for i in ids)
