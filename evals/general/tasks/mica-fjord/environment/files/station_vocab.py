"""Mica-Fjord station vocabulary container.

This module is the ONLY supported home of the ``Vocab`` dataclass.  Anything
that is pickled as a vocabulary for the Mica-Fjord release must be an instance
of ``station_vocab.Vocab``: the release verifier imports this exact module and
unpickles against it.  A class defined in some other module (or a hand-rolled
lookalike) will fail to unpickle / fail the isinstance check inside the
verifier, because pickle stores the *module path* of the class.
"""
from dataclasses import dataclass
from typing import Dict, Iterable, List

SPECIALS = ("<pad>", "<unk>")


@dataclass
class Vocab:
    """Parallel word-to-index / index-to-word maps that must be exact inverses."""

    word2idx: Dict[str, int]
    idx2word: Dict[int, str]

    def check_inverse(self) -> bool:
        """True iff the two maps are exact inverses of each other."""
        if len(self.word2idx) != len(self.idx2word):
            return False
        if len(set(self.word2idx.values())) != len(self.word2idx):
            return False
        if len(set(self.idx2word.keys())) != len(self.idx2word):
            return False
        for word, idx in self.word2idx.items():
            if self.idx2word.get(idx) != word:
                return False
        return True

    def size(self) -> int:
        return len(self.word2idx)

    def encode(self, tokens: Iterable[str]) -> List[int]:
        unk = self.word2idx.get("<unk>")
        return [self.word2idx.get(t, unk) for t in tokens]

    def decode(self, ids: Iterable[int]) -> List[str]:
        return [self.idx2word.get(int(i), "<unk>") for i in ids]
