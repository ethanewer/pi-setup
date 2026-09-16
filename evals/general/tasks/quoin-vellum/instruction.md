# Train a gensim topic model on a real corpus

## Situation

A genuine upstream machine-learning library is installed on this machine, built
from the source tree that was cloned for you at **`/app/src`**: the `gensim`
gem-sim library, version 4.4.0, installed in editable mode so that `import
gensim` resolves to the edited source under `/app/src` (editable installs load
code directly from that tree). The numeric thread pools have been pinned to one
core, so treat this as a single-CPU machine.

A text corpus is on disk at **`/app/corpus/docs.txt`**. It contains one document
per line; each line is a whitespace-separated sequence of lower-case English
words. The documents are drawn from several latent, semantically distinct topics,
and the topic mixture is *not* labelled anywhere you can see: you must make the
model recover it.

## Deliverable

Write one executable script at **`/app/train_topics.py`**. It must be a generic
training pipeline with this exact command-line contract:

```
python3 /app/train_topics.py <corpus_dir> <model_out.model>
```

- `<corpus_dir>` is a directory containing a file `docs.txt` in the same
  one-document-per-line format as the visible corpus.
- The script reads that corpus, trains a topic model with **gensim's own API**,
  and writes a trained model to `<model_out.model>` **serialised in gensim's own
  binary format** (`Model.save`).

The script will be executed against corpora you have never seen, so it must be
generic — no hard-coded topic counts, no corpus-specific constants. It must work
on any corpus directory in that format.

The verifier will, for each of several held-out corpora, run your script, then
**load the model back from disk with gensim's own loader** and score it on two
qualities:

1. **topical coherence** — how well the words in each learned topic hang
   together as measured by gensim's `CoherenceModel` (c_v variant);
2. **topic purity** — whether the most probable words of each learned topic all
   come from a single coherent semantic cluster rather than being scattered
   across several.

A model that captures the real topical structure of the corpus scores highly on
both; a degenerate model (a single topic for everything, an obviously wrong
number of topics, or one that was never really trained) scores poorly. All three
held-out corpora must pass, so the pipeline must generalise and must pick
sensible settings by itself.

## What already exists

- `/app/src` — the gensim 4.4.0 source tree (already built and installed).
- `/app/corpus/docs.txt` — a visible corpus to develop and sanity-check against.
- `gensim`, `numpy`, `scipy`, `smart_open` — installed, importable.

You may read/modify `/app/src` and any part of the installed library, and you may
run and iterate on your script against `/app/corpus/docs.txt` as much as you
like. The number of latent topics in the corpus is for you to determine.

## Output contract

Create and leave **`/app/train_topics.py`** executable, implementing the
contract above. That file is the only deliverable that matters; everything else
you produce is workspace.
