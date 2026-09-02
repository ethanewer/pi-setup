# Index the observatory glossary

You are curating the **Opal Lexicon** for a small observatory-log pipeline. A
vocabulary object — a container exposing parallel word-to-index and
index-to-word mappings — must be persisted to disk as a pickled object that
unpickles correctly inside a downstream checker, and its size must agree
exactly with the row count of the shipped embedding matrix.

Everything runs in `/app` with Python 3.12 **standard library only** (no
numpy, no third-party packages, no network).

## Provided fixture (do not modify)

- `/app/data/corpus.txt` — the observatory log, a UTF-8 text file. Its exact
  original bytes must remain unchanged (the checker verifies a checksum).

## Tokenization rule (applies to any corpus in this format)

- Read the file line by line. A **token** is a maximal run of non-whitespace
  characters (`line.split()` semantics). Blank or whitespace-only lines
  contribute no tokens.
- The **frequency** of a token is its total number of occurrences across the
  whole file.

## Vocabulary ordering rule

The vocabulary is the list of distinct tokens ordered by:
1. frequency, **descending**;
2. ties broken by ascending token (Python string `<` on the raw token).

`idx2word` is exactly that ordered list; `word2idx` maps each token to its
0-based position in it.

## Deliverables (all required, all under `/app`)

1. **`/app/vocab_lib.py`** — a module defining the vocabulary container:

   ```python
   from dataclasses import dataclass
   from typing import Dict, List

   @dataclass
   class Vocab:
       word2idx: Dict[str, int]
       idx2word: List[str]

       def size(self) -> int: ...          # number of tokens
       def check_inverse(self) -> bool: ...# True iff the two maps are exact inverses
   ```

   The class **must** be named `Vocab`, live in `/app/vocab_lib.py`, and
   expose the attributes `word2idx` (dict token -> int) and `idx2word`
   (list of tokens). `check_inverse()` returns True exactly when
   `word2idx` and `idx2word` are exact inverses of each other (same size,
   no duplicate/out-of-range indices, `idx2word[word2idx[t]] == t` for every
   token, and every list slot covered).

2. **`/app/build_vocab.py`** — a reusable CLI builder:

   ```
   python3 /app/build_vocab.py <corpus.txt> <out_dir>
   ```

   It reads any corpus in the format above and writes into `<out_dir>`:
   - `vocab.txt` — one token per line, in vocabulary order (empty file if the
     corpus has no tokens);
   - `embeddings.csv` — one line per token, **16 comma-separated finite
     floats** per line; line `i` is the embedding of token `i`. The values
     must be produced by a **deterministic** scheme of your choice (re-running
     the command on the same corpus must reproduce the file byte-for-byte),
     and each row must contain at least one non-zero value;
   - `vocab.pkl` — a pickled instance of the `Vocab` class from
     `vocab_lib` (import it as `import vocab_lib` / `from vocab_lib import
     Vocab`), built from the `word2idx` / `idx2word` defined above.

   The builder must be **importable-safe**: it must work when invoked from any
   working directory. It must not crash on a corpus with zero tokens.

3. **`/app/vocab.txt`, `/app/embeddings.csv`, `/app/vocab.pkl`** — the
   artifacts produced by running

   ```
   python3 /app/build_vocab.py /app/data/corpus.txt /app
   ```

## Invariants the checker enforces (visible and on hidden corpora)

For every corpus it gives your builder — including a normal corpus with
duplicated and punctuation tokens, a corpus with **only blank lines**
(zero tokens), and a corpus where every token occurs exactly once (all
frequencies tie) — the checker runs your `build_vocab.py` and requires:

- `vocab.txt` contains exactly the distinct tokens in the ordering rule
  above (one per line; empty file when there are none);
- `vocab.pkl` unpickles **inside the checker** (which imports from `/app`)
  into an object whose `word2idx` / `idx2word` are exact inverses and whose
  `size()` equals the number of embedding rows;
- `embeddings.csv` has exactly one line per token, each with 16 finite
  comma-separated floats, at least one non-zero per row;
- running the builder twice on the same corpus yields **byte-identical**
  `vocab.txt`, `embeddings.csv` and `vocab.pkl`;
- `/app/vocab.txt`, `/app/embeddings.csv`, `/app/vocab.pkl` match exactly
  what the builder produces for the shipped `/app/data/corpus.txt`.

A vocabulary object that unpickles into the wrong module path (e.g. a class
defined in a throwaway script instead of `vocab_lib`), has mappings that are
not exact inverses, or whose size disagrees with the embedding row count
fails the check.

## Constraints

- Do not modify `/app/data/corpus.txt`.
- Standard library only; deterministic; no network.
