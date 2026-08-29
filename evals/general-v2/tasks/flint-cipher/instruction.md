# Flint Cipher — build a small CPU-only NLP training artifact set

You are given a plain-text multilingual text corpus and a labelled training +
development split, all under `/app/data/`. Your job is to produce a complete,
reusable NLP training artifact set. There are **three stages** that must all be
satisfied; each feeds the next. Work entirely inside `/app`.

## Provided data (read-only inputs, do not modify)

- `/app/data/corpus.txt` — the source plain-text corpus (whitespace/newline
  separated words, punctuation, blank lines, some title-cased words).
- `/app/data/train.tsv` — one labelled document per line: `lang<TAB>text`.
  Four languages: `en`, `fr`, `de`, `es`. 30 documents per language.
- `/app/data/dev.tsv` — the same schema, held-out from training. 10
  documents per language. This is your evaluation set.

## Deliverables (all must exist exactly at these paths)

1. `/app/vocab.txt` — one word per line, the filtered vocabulary.
2. `/app/build_vocab.py` — a reusable vocabulary builder.
3. `/app/tokenizer/bpe.model` — a saved byte-pair-encoding tokenizer model.
4. `/app/build_tokenizer.py` — a reusable BPE trainer.
5. `/app/train.py` — trains + evaluates the multilingual classifier.
6. `/app/classifier_snapshot.npz` — the trained classifier snapshot.
7. `/app/eval_metrics.json` — evaluation metrics from the held-out dev split.
8. `/app/predict.py` — reuses the saved snapshot to classify new documents.

You may add helper files, but these 8 must be present and functional.

---

## Stage 1 — vocabulary with frequency filtering

`/app/build_vocab.py` must read a plain-text corpus and write a frequency-filtered
vocabulary. **Required behaviour:**

- Word tokens are normalised to lower case. Split on any run of
  non-alphanumeric characters (`\w+`, Unicode-aware). Blank lines and stray
  punctuation must not crash it and contribute no tokens.
- Keep every word whose occurrence count in the corpus is `>=` a threshold.
- The following 25 terms MUST each appear in the output no matter how rare
  they are in the corpus (they are the fixed "required set"):

  `aegis, balmweaver, calmstone, dunecrest, earthenmark, falconquill,
  glintshard, harborward, ironweald, junipergate, kelvinvale, lumenhold,
  meridianstone, northwell, oakhurst, pebblecrag, quillwillow, reedskiff,
  slopehollow, sunveil, thornbraid, unbarrow, vaultpine, wrenshaw, yarrowkeep`

- CLI (this exact interface is used by the verifier):

  ```
  python3 /app/build_vocab.py --corpus <file.txt> --out <out.txt> --min-count <int>
  ```

  The default `--min-count` is 2. Output: one vocabulary word per line,
  sorted, with a trailing newline.

**Edge cases the hidden test probes:** a required term whose raw count is `1`
(below the threshold) must STILL survive because it is in the required set; a
long list of words that appear only once must be filtered out; the corpus may
contain blank lines, whitespace-only lines, and punctuation-only lines.

## Stage 2 — bounded deterministic BPE tokenizer

`/app/build_tokenizer.py` trains a byte-pair-encoding tokenizer with the
`tokenizers` library and saves the model. CLI:

```
python3 /app/build_tokenizer.py --corpus <path> --out <out.bpe> \
                                --vocab-size <int> --min-frequency 1
```

- Train a BPE model (`tokenizers.models.BPE`) with a ByteLevel pre-tokenizer
  and ByteLevel decoder, `unk_token="<unk>"`, and stash the `special_tokens`
  as `["<unk>"]` in an `BpeTrainer`. The byte alphabet guarantees every string
  is representable, and the library guarantees the merge priorities (and thus
  the result) are deterministic for a fixed corpus and seed-free training.
- The vocabulary must never exceed the requested `--vocab-size`.
- Save the full tokenizer (single file, reloadable with
  `tokenizers.Tokenizer.from_file`) to the given `--out`.

The verifier **re-runs `build_tokenizer` on a hidden corpus**, reloads the
model, checks `len(model.get_vocab()) <= vocab_size`, and checks that
`decode(encode(text))` reproduces an input sentence (round-trip).

Your shipped `/app/tokenizer/bpe.model` must be trained on
`/app/data/corpus.txt` with `--vocab-size 512 --min-frequency 1`.

## Stage 3 — multilingual classifier with held-out evaluation

`/app/train.py` must train a tiny classifier on `/app/data/train.tsv`,
evaluate on `/app/data/dev.tsv`, and write:

- `/app/classifier_snapshot.npz` — enough frozen state that `/app/predict.py`
  can classify brand-new documents **without re-training**. Store that state
  under exactly these keys: `feature` (the char n-gram feature list the model
  was trained on), `classes` (the class labels), `coef` (the per-class
  coefficient matrix, rows = classes, columns = features) and `intercept`
  (the per-class intercept vector).
- `/app/eval_metrics.json` — must contain at least `overall_accuracy`
  and `per_language` (a dict mapping **each** of the four languages `en`,
  `fr`, `de`, `es` to its dev accuracy), plus whatever else you find useful.

CLI (exact interfaces; both optional defaults):

```
python3 /app/train.py --train /app/data/train.tsv --dev /app/data/dev.tsv \
                      --snapshot /app/classifier_snapshot.npz \
                      --metrics /app/eval_metrics.json
python3 /app/train.py --train ... --dev ... --snapshot ... --metrics ... \
                      --seed <int>          # optional: seed any randomness (default 0)
python3 /app/predict.py [snapshot.npz] [input.tsv] [output.txt]
```

`predict.py` reads a label/document tsv (or bare-text lines) and writes one
predicted label per input line — to the given output file, or to stdout if no
output file is given. It must return a prediction for every non-empty line,
including a document whose text has **no usable features** (return the
class with the largest intercept as the default). A line with a missing tab is
treated as unlabelled text to classify.

**The shipped model must reach on the dev split:** overall accuracy
`>= 0.90` and, for each of `en`, `fr`, `de`, `es`, accuracy `>= 0.85`.

Suggested approach (fast on CPU; you are free to improve it):

- Represent each document as a bag of character n-grams (e.g. 2–4 gram
  sequences over lower-cased alpha characters).
- Train `sklearn.linear_model.LogisticRegression` (multinomial, `lbfgs`,
  fixed `random_state`, `max_iter>=2000`).
- Squeeze the char n-gram feature list into the snapshot so `predict.py` can
  reuse it exactly.

**Verifier re-evaluates the frozen snapshot on a brand-new held-out document
set** (same four languages, documents the model never saw). It checks overall
accuracy `>= 0.90` and per-language accuracy `>= 0.85` on that hidden set too
— your model must *generalise*, not memorise training rows.

---

## Rules

- Work only under `/app`. Do not touch `/logs`, `/tests`, or anything outside
  `/app`.
- deterministic seeds: fix any randomness in training.
- Keep runtime modest (the classifier must train in well under a minute on
  one CPU core).