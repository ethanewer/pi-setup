# Zephyr Bridge — tokenizer, embeddings, classifier and vocab shipping bundle

## Overview

The **Zephyr** text-tools team ships a small, hand-built language bundle over a
synthetic two-class "product verdict" corpus (`neg` / `pos`). The release is
frozen except for the analytics pipeline, which is *your* job to build and wire
into the provided loader.

You must produce a **single, reproducible runner** (`/app/run.sh`) and the
artifacts it emits, so that the provided loader (`/app/zeph_loader.py`) can
consume every one of them — a vocabulary file, a merge-rule file, a 300-dim
embedding matrix, a fasttext-style text classifier under a size budget, a
per-model metrics table, and a pickled vocabulary dataclass whose maps are
exact inverses sized to the embedding rows.

Work only under `/app`. Everything is CPU-only, no network.

## What is provided (do not modify these)

* `/app/zeph_loader.py` — the shipping loader / library. **All tokenization,
  holdout splitting, feature pooling and the `Vocab` dataclass must come from
  this module.** Do not edit it.
* `/app/gen_corpus.py` — deterministic synthetic corpus generator (used to
  regenerate fixtures; the verifier uses it to build fresh/edge corpora).
* `/app/data/reviews.tsv` — the shipped labeled corpus: one row per line,
  `label<TAB>text`, labels `neg` / `pos`. 2600 rows.

`zeph_loader` is importable as `import zeph_loader as zl` from `/app`.

## Deliverable contract

Write an executable runner

```
bash /app/run.sh [CORPUS_TSV] [OUTDIR]
```

* Called with **no arguments**, it must process the shipped corpus
  `/app/data/reviews.tsv` and write the deliverables **into `/app/`**.
* Called with `CORPUS_TSV OUTDIR`, it must process any corpus in the same
  format (label<TAB>text) and write the identical artifacts into `OUTDIR`.
  The verifier calls it this way on fresh and edge corpora.

The runner and its helpers may be organised however you like, but the runner
itself must be at `/app/run.sh` and be re-runnable (idempotent). Your pipeline
is allowed to re-run a full build each invocation.

## Artifacts (all written by your runner)

### 1. `/app/vocab.txt`
One token per line, no blank lines, no line may contain internal whitespace.
The line number (0-based) is the token index. The set of tokens must be the
word vocabulary learned from the corpus. Consumed by `zl.load_vocab`.

### 2. `/app/merges.txt`
One merge rule per line: two whitespace-free symbols separated by a single
space, e.g. `ab c`. Rules form a consistent character-level BPE chain: each
rule's two symbols are either single characters or symbols introduced by an
earlier rule. Consumed by `zl.load_merges` and `zl.apply_merges`. Provide a
substantial rule set (several hundred rules).

### 3. `/app/embeddings.npy`
A `numpy` array of shape `(V, 300)` of dtype `float32` / `float64`, where `V`
is exactly the number of tokens in `vocab.txt`; row `i` is the embedding of
`vocab.txt[i]`. These are genuinely trained, distributional vectors
(word2vec-style): tokens that frequently co-occur must lie close together and
tokens from opposite classes must be separated (the verifier checks cosine
separation of frequently co-occurring token groups on the shipped corpus).

### 4. `/app/metrics.csv`
A per-model metrics table with the exact header:

```
model,correlation,error,penalty,dof
```

Exactly **three** rows, one per candidate embedding model, named `pmi`,
`cbow` and `skipgram` (in any row order). For each row:
* `correlation` — mean cosine similarity (in `[0,1]`) of that model's
  mean-embedding features to a reference embedding's features on a sample of
  reviews;
* `error` — `1 - correlation` of the same comparison (`[0,1]`);
* `penalty` — `model_matrix_bytes / 8MiB` (`[0,1]`);
* `dof` — a positive integer: the intrinsic dimension (number of singular
  values of the centered embedding matrix above 5% of the largest).

The values must be **computed from the models you actually trained** (not
stubbed). The verifier checks header, row names, numeric ranges and that
`error ≈ 1 - correlation` within 0.05.

### 5. `/app/vocab.pkl`
A pickled instance of `zl.Vocab`, unpicklable via the shipped loader class:
`wl.word2idx` (token -> index) and `wl.idx2word` (index -> token) must be
exact inverses (`wl.check_inverse()` true), sized exactly to the number of
embedding rows, and token-consistent with `vocab.txt`. Because `Vocab` lives
in `zeph_loader`, import it from that module and pickle an instance of it so
it unpickles inside the verifier.

### 6. `/app/model.pkl`
A pickled dict `{"clf": <fitted classifier>, "classes": [sorted label names]}`.
The classifier must be **fasttext-style**: a linear model fitted on the
mean-pooled word-embedding features of each review (see `zl.word_features`),
so its `coef_` width equals the embedding width (300). Serialized size must be
under **8 MiB**. The verifier reloads it, recomputes the deterministic holdout
with `zl.split_corpus`, and requires a holdout **classification accuracy
`>= 0.85`** on the shipped corpus. Two label encodings are equivalent: fit the
classifier on the label names themselves (predictions are `neg`/`pos` strings)
or on their indices into `classes` (predictions are integers) — the verifier
normalises predictions to class indices, so only genuine holdout accuracy is
graded.

## Loader conventions (use these exactly)

* `zl.tokens_of(text)` — word tokens (lowercase alphanumerics; punctuation is
  a separator; a run with no word characters yields no tokens).
* `zl.read_corpus(path)` — parses `label<TAB>text`, skipping blank lines,
  rows without a bare TAB, and rows whose label/text strip to empty.
* `zl.split_corpus(rows)` — a deterministic ~20% holdout split (keyed on text
  hash). Use it so the verifier can reproduce your test set exactly.
* `zl.Vocab(word2idx, idx2word)` — the dataclass to serialize.
* `zl.load_vocab`, `zl.load_merges`, `zl.apply_merges` — the loaders your
  `vocab.txt` / `merges.txt` must satisfy.
* `zl.word_features(text, vocab, emb)` — mean of the word-embedding rows of a
  text (fasttext-style pooling; empty input -> zero vector). This is the
  classifier feature function.

## Robustness (what the verifier probes)

The checker does not only read your shipped files: it **re-runs your runner**
on synthetic corpora built by `gen_corpus.py` and re-checks *all* of the above
structural invariants plus classifier accuracy on those corpora. In particular
the second hidden corpus is an **edge corpus** that mixes in:

* fully blank lines,
* punctuation-only rows (no word tokens),
* digit-only rows,
* very short (single-token) rows,
* duplicate rows, and
* rows with no TAB separator.

Your pipeline must not crash on such rows, must skip malformed rows through
`zl.read_corpus`, and must still produce vocab/merges/embeddings/metrics/vocab
consistent with the *valid* rows, plus a loadable classifier that reaches a
meaningful accuracy on that corpus's deterministic holdout.

## Requirements checklist

* Train real 300-dim embeddings that generalise (co-occurrence structure).
* Train a real fasttext-style classifier that clears the accuracy floor while
  staying under the 8 MiB size budget.
* Keep `vocab.txt`, `embeddings.npy` rows, `vocab.pkl` and `idx2word` all in
  exact bijection.
* Produce a genuine, internally consistent `metrics.csv`.
* Make `/app/run.sh` reproducible on **any** corpus in the shipped format.
* Do not modify `zeph_loader.py`, `gen_corpus.py`, or `/app/data/reviews.tsv`.

## Checking your work

From `/app`, after running `bash /app/run.sh`, you can sanity-check with:

```python
import pickle, numpy as np, zeph_loader as zl
v = pickle.load(open('/app/vocab.pkl','rb'))
E = np.load('/app/embeddings.npy')
assert v.check_inverse() and v.size() == E.shape[0]
print(open('/app/metrics.csv').read())
```
