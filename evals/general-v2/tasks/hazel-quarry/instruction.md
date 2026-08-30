# Hazel Quarry — build a frequency-filtered search lexicon

The Hazel Quarry heritage team is building the word index (lexicon) that backs
a full-text search over their archive scans. You must write a **reusable
vocabulary builder** and run it on the provided corpora to produce the shipped
lexicon. The program must work on **any** input conforming to the contract
below — the grader re-runs it on hidden corpora, hidden protected-term lists,
and different thresholds.

## Provided data (read-only; do not modify)

- `/app/data/corpus_aria.txt` — plain-text corpus file 1
- `/app/data/corpus_borealis.txt` — plain-text corpus file 2
- `/app/data/required_terms.txt` — the protected terms, one per line

The corpora contain lowercase and title-cased words, ALL-CAPS words, words
wrapped in punctuation, numeric tokens (e.g. `1847`), accented words (e.g.
`café`, `Zürich`), blank lines, whitespace-only lines and punctuation-only
lines. The **lexicon** is built from *both* corpus files together.

## Deliverables (both required)

1. `/app/lexicon.py` — the reusable vocabulary builder with exactly this CLI:
   ```
   python3 /app/lexicon.py --corpus <file.txt> [--corpus <file.txt> ...] \
                           --required <terms.txt> --min-count <int> --out <out.txt>
   ```
   `--corpus` may be given one or more times; counts are aggregated across all
   given corpus files.

2. `/app/lexicon.txt` — the lexicon produced by running your program on the
   provided visible data with `--min-count 4`:
   ```
   python3 /app/lexicon.py \
       --corpus /app/data/corpus_aria.txt --corpus /app/data/corpus_borealis.txt \
       --required /app/data/required_terms.txt --min-count 4 --out /app/lexicon.txt
   ```

## Required behaviour of `/app/lexicon.py`

- **Tokenization**: the text of every corpus file is lower-cased, then split
  into tokens where a token is any maximal run of word characters
  (`\w+`, Unicode-aware — letters, digits and underscore; hyphens and other
  punctuation are separators, so `slate-bole` yields the two tokens `slate`
  and `bole`). Blank, whitespace-only and punctuation-only lines contribute
  no tokens but must never crash the program.
- **Term frequency**: a token's count is its total number of occurrences
  summed over **all** `--corpus` files.
- **Protected terms**: the `--required` file lists protected terms, one per
  line; surrounding whitespace is trimmed, blank lines are ignored, and terms
  are compared case-insensitively after lower-casing.
- **Filtering rule**: a token is kept in the lexicon if
  `count(token) >= min_count` **or** the token is a protected term.
  Protected terms are kept **no matter how rare** — including a protected
  term whose count is exactly 1 (below the threshold) and even one that
  appears **nowhere** in the corpora (count 0). Its inclusion must not depend
  on the threshold value.
- **Output**: one token per line, sorted in ascending order (plain string
  sort), deduplicated, with a single trailing newline. No extra text.
- Exit status 0 on success.

## The 30 protected terms

Every one of the following MUST appear in `/app/lexicon.txt` regardless of its
corpus frequency (several occur fewer than 4 times, and one does not occur at
all):

`adzebind, alderfen, briarlock, brackenmoor, claymarrow, cinderwart,
dellhollow, dunlinscar, ellerypole, emberloam, fennelcrag, gorsevale,
hazelshaft, inkwellrow, juniperflake, kelpbrack, loamquarry, marlstone,
nettleward, osierfen, peatwhorl, quarryfield, rushenmere, slatebole,
tarnwick, umberfold, vetchmoor, whitmoor, yewsprig, zincgate`

(NB: the list above is prose; the authoritative protected list is the 30 terms
in `/app/data/required_terms.txt`.)

## Edge cases the grader probes with hidden inputs

- A protected term with raw count **1** (below the threshold) must still be kept.
- A protected term that occurs **zero** times must still be kept.
- A protected term written in the required file with **mixed case** or
  surrounding whitespace must still match its lowercase corpus token.
- Counts must **aggregate across multiple `--corpus` files** (a token seen
  twice in file 1 and once in file 2 has count 3).
- Boundary filtering: tokens with count exactly `min_count` are kept; tokens
  with count exactly `min_count - 1` are dropped (unless protected).
- A long tail of words occurring only once (below threshold, unprotected)
  must be filtered out; the resulting lexicon must still be sizeable (the
  grader checks it is at least as large as the true filtered vocabulary).
- Blank lines, whitespace-only lines and punctuation-only lines must not
  crash the program or add tokens.

## Constraints

- The grader runs `/app/lexicon.py` **unchanged** on hidden corpora, hidden
  required-term files, and hidden `--min-count` values, so do not hard-code
  the visible data, the 30 terms, or the threshold 4.
- Do not modify anything under `/app/data`.
- No network access; Python 3.12 standard library only.
