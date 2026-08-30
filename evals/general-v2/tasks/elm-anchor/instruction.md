# Elm-anchor: emit vocabulary and merge rules for the Merm loader

The Merm tokenizer ships with a strict loader (`/app/merm_loader.py`, **do not
modify it**). It accepts a vocabulary file and a merge-rule file in an exact
text format, and it *fails to load* (raises `ValueError`) on any deviation —
blank lines, stray whitespace, duplicate tokens, or a merge rule that
references a symbol introduced by a LATER rule.

Your job: implement the BPE learner that emits both files, and run it on the
shipped corpus. There is no network; standard-library Python only.

## Deliverables (all required, all under `/app`)

1. **`/app/emit.py`** — a reusable learner:
   ```
   python3 /app/emit.py <corpus.txt> <outdir>
   ```
   It reads any UTF-8 corpus (whitespace-separated words) and writes
   `<outdir>/vocab.txt` and `<outdir>/merges.txt` per the learning procedure
   below (create `<outdir>` if missing; re-running must be idempotent).

2. Run it on the shipped corpus:
   ```
   python3 /app/emit.py /app/data/corpus.txt /app
   ```
   leaving **`/app/vocab.txt`** and **`/app/merges.txt`** in place.

The grader re-runs `/app/emit.py` unchanged on hidden corpora (different
alphabets, sizes, and repetition structure) and checks both emitted files —
their content must match the reference learner exactly.

## Learning procedure (normative — the grader compares byte-exact output)

1. Read the corpus; **pre-tokenize** by splitting on whitespace runs
   (`corpus.split()`), and count the frequency of each distinct word.
2. **Base alphabet**: the set of distinct characters across all words.
   `vocab.txt` starts with these characters, one per line, **sorted by Unicode
   code point**.
3. Represent each distinct word as a list of its characters.
4. **Merge loop** — repeat until the stop condition:
   a. Count every adjacent symbol pair across words, weighted by word
      frequency.
   b. Choose the pair with the **highest count**; break count ties by choosing
      the lexicographically smallest pair (compare `left`, then `right`, by
      Unicode code points).
   c. **Stop condition**: stop BEFORE learning a merge whose count is `< 2`,
      or once `300` merges have been learned, whichever comes first.
   d. Append the merge: the line `left right` goes into `merges.txt` (in
      learned order), the token `left+right` is appended to `vocab.txt`, and
      the merge is applied to every word (scan each word left to right,
      replacing non-overlapping occurrences of the adjacent pair with the
      merged token; a triple `a a a` becomes `aa a`).
5. `merges.txt` contains exactly the learned rules, one `left right` pair per
   line in learned order. `vocab.txt` is therefore `base alphabet (sorted)`
   followed by `merged tokens in the order they were introduced`.

## Loader conventions (enforced by `merm_loader.py`)

- `vocab.txt`: one token per line; no blank lines; no leading/trailing or
  internal whitespace; no duplicates.
- `merges.txt`: one rule per line, exactly two whitespace-free symbols
  separated by a single space; rule i's symbols must each be a single
  character or a merged token introduced by an earlier rule, and `left+right`
  must exist in `vocab.txt`.
- Encoding (reference, used by the grader): split text on whitespace; for each
  word start from its characters and repeatedly apply the applicable rule with
  the smallest line number, replacing all its occurrences left-to-right, until
  no applicable rule remains; map each resulting symbol to its vocab line
  number (0-based).

## Constraints

- The emitted files must load cleanly with the shipped loader on every hidden
  corpus, and the tokenization of probe strings must match the reference.
- Deterministic: same corpus → byte-identical output files.
- Do not modify `/app/merm_loader.py` or `/app/data/corpus.txt`.
