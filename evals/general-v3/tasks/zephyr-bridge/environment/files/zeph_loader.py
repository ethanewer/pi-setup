"""zeph_loader.py -- the shipping loader for the `zephyr` language bundle.

Every artifact in a `zephyr` pipeline (*vocab.txt*, *merges.txt*, *embeddings
matrix*, *metrics.csv*, *vocab.pkl*, model pickle) is consumed via the helpers
on this module.  Do NOT modify this file.  Your programs may import it freely
from `/app` (it is on the import path).

Contracts implemented here are the single source of truth for:
  * the on-disk shape of a subword/word vocabulary and its serialised dataclass,
  * the whitespace/merge tokenizer convention the classifier features follow,
  * the deterministic holdout split used to score a classifier.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Dict, List, Tuple

import numpy as np

# ----------------------------------------------------------------------------
# corpus / holdout helpers
# ----------------------------------------------------------------------------

_TOKEN_RE = re.compile(r"[a-z0-9']+")


def tokens_of(text: str) -> List[str]:
    """Word-level token list for classifier features (lowercased alpha-num).

    Whitespace and punctuation are separators; a run with no word characters
    (e.g. ``!!``) yields no tokens.  This is the tokenizer convention shared by
    the fasttext-style mean-embedding classifier.
    """
    return _TOKEN_RE.findall(text.lower())


def read_corpus(path: str) -> List[Tuple[str, str]]:
    """Read ``label<TAB>text`` rows.  Blank lines, lines without a bare TAB
    separator, and rows whose label or text strip to empty are skipped; the
    remaining rows are returned in file order.
    """
    rows: List[Tuple[str, str]] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if "\t" not in line:
                continue
            label, text = line.split("\t", 1)
            if not label.strip() or not text.strip():
                continue
            rows.append((label.strip(), text))
    return rows


def split_corpus(rows: List[Tuple[str, str]]) -> Tuple[List[Tuple[str, str]], List[Tuple[str, str]]]:
    """Deterministic ~20% holdout split keyed on the text hash.

    The same rows always produce the same train/test partition (across process
    runs, across the agent's trainer and the verifier), which lets the verifier
    reproduce the classifier's test set exactly.
    """
    def seg(i: int) -> str:
        label, text = rows[i]
        return hashlib.sha1((label + "#" + text).encode()).hexdigest()

    # stable order independent of file order
    order = sorted(range(len(rows)), key=seg)
    test_idx = set(order[i] for i in range(len(order)) if i % 5 == 0)
    train = [rows[i] for i in order if i not in test_idx]
    test = [rows[i] for i in order if i in test_idx]
    return train, test


# ----------------------------------------------------------------------------
# 2. vocabulary / vocabulary dataclass
# ----------------------------------------------------------------------------

@dataclass
class Vocab:
    """The shipped vocabulary value object.

    ``word2idx`` and ``idx2word`` MUST be exact inverses of one another and
    sized to the embedding matrix rows (emb[i] is the vector for the token
    ``idx2word[i]`` / ``vocab.txt`` line ``i``).
    """
    word2idx: Dict[str, int]
    idx2word: Dict[int, str]

    def size(self) -> int:
        return len(self.word2idx)

    def check_inverse(self) -> bool:
        """Both maps must be exact inverses (word<->index bijection)."""
        return (
            len(self.word2idx) == len(self.idx2word)
            and all(self.idx2word.get(v) == w for w, v in self.word2idx.items())
            and all(self.word2idx.get(w) == v for v, w in self.idx2word.items())
        )


def load_vocab(path: str) -> List[str]:
    """Load a *vocab.txt* (one token per line) into a list.

    The verifier uses this loader, so the file MUST be one token per line and
    contain no line whose token has internal whitespace.
    """
    toks: List[str] = []
    with open(path, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            tok = line.strip()
            if not tok:
                continue
            if " " in tok or "\t" in tok:
                raise ValueError("vocab token %r (line %d) must be a single unit" % (tok, i))
            if tok in toks:
                raise ValueError("duplicate vocab token %r (line %d)" % (tok, i))
            toks.append(tok)
    return toks


# ----------------------------------------------------------------------------
# 3. merge-rule file format (subword BPE merges)
# ----------------------------------------------------------------------------

def load_merges(path: str) -> List[Tuple[str, str]]:
    """Load a *merges.txt*: exactly two whitespace-free symbols per line."""
    pairs: List[Tuple[str, str]] = []
    with open(path, encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split(" ")
            if len(parts) != 2 or not parts[0] or not parts[1]:
                raise ValueError("merge line %d must be '<s1> <s2>': %r" % (i, line))
            pairs.append((parts[0], parts[1]))
    return pairs


def apply_merges(text: str, merges: List[Tuple[str, str]]) -> List[str]:
    """Greedy character-level BPE decode of ``text`` using ``merges``.

    ``merges`` is ordered highest-priority first; each entry joins two adjacent
    units whose concatenation is the higher-level unit.  This is the loader's
    subword tokenizer (independent of the word-level classifier tokenizer).
    """
    units: List[str] = []
    for word in tokens_of(text):
        parts = [c for c in word]
        while True:
            chosen = None
            for left, right in merges:
                for i in range(len(parts) - 1):
                    if parts[i] == left and parts[i + 1] == right:
                        chosen = (left, right, i)
                        break
                if chosen is not None:
                    break
            if chosen is None:
                break
            left, right, i = chosen
            parts[i : i + 2] = [left + right]
        units.extend(parts)
    return units


# ----------------------------------------------------------------------------
# 4. feature / embedding helpers (fasttext-style classifier input)
# ----------------------------------------------------------------------------

def word_features(text: str, vocab: Vocab, emb: np.ndarray) -> np.ndarray:
    """Mean of the word-embedding rows of ``text`` (fasttext-style pooling).

    Unknown / absent words are dropped (they contribute nothing).  Empty input
    (or a text with no known words) yields the zero vector of embedding width.
    """
    width = emb.shape[1]
    idxs = [vocab.word2idx[w] for w in tokens_of(text) if w in vocab.word2idx]
    if not idxs:
        return np.zeros(width, dtype=np.float32)
    return np.mean(emb[np.asarray(idxs, dtype=np.int64)], axis=0).astype(np.float32)


def vectorize(texts, vocab: Vocab, emb: np.ndarray) -> np.ndarray:
    out = np.empty((len(texts), emb.shape[1]), dtype=np.float32)
    for i, t in enumerate(texts):
        out[i] = word_features(t, vocab, emb)
    return out