# RIBES translation-quality scoring breaks on empty inputs

## Situation

`/app/src` is a shallow, pinned clone of the NLTK natural-language toolkit
(`https://github.com/nltk/nltk`), checked out at upstream commit
`a167389c027a02a9d1f019630ed827f4069b3353`, and installed from that tree in
editable (development) mode, so `import nltk` resolves to the checked-out
Python source and edits you make are picked up immediately. Python 3.12 is
installed together with numpy, pytest 8.4, pytest-mock, regex, pyyaml, click,
tqdm, joblib and defusedxml. There is **no network** at trial time: everything
you need is already in the image; `pip` and `git fetch` will not work.

## The bug

The RIBES score is a machine-translation quality metric that compares a
candidate (hypothesis) translation against one or more reference translations.
The toolkit exposes it as `sentence_ribes(references, hypothesis)`, which
scores one candidate against a list of reference sentences, and
`corpus_ribes(list_of_references, hypotheses)`, which scores a whole parallel
corpus and returns the mean of the per-sentence scores.

In this checkout the scorer crashes whenever the data is empty:

- a candidate translation with **no tokens** (`sentence_ribes([["a"]], [])`)
  dies with `ZeroDivisionError: division by zero`;
- a sentence whose reference list is empty (`sentence_ribes([], ["a"])`)
  silently returns an impossible negative score `-1.0`;
- an **empty corpus** (`corpus_ribes([], [])`) also dies with
  `ZeroDivisionError: division by zero`;
- a corpus whose number of reference sets does not match its number of
  hypotheses is silently mis-scored instead of being rejected.

The intended behaviour is:

| input | intended result |
| --- | --- |
| empty hypothesis (no tokens) | `0.0` |
| empty reference list for a sentence | `0.0` |
| empty corpus | `0.0` |
| reference-set count != hypothesis count | a clear `ValueError` |
| anything genuinely non-empty | exactly the same score as now |

## Reproducing the failure

```
python3 /app/probe_ribes.py
```

prints each of the four cases above and reports which ones are broken. One-line
confirmations of the same crash:

```
python3 -c "from nltk.translate.ribes_score import sentence_ribes, corpus_ribes; print(sentence_ribes([['a']], []))"
python3 -c "from nltk.translate.ribes_score import sentence_ribes, corpus_ribes; print(corpus_ribes([], []))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that all four rows of the
table above hold, while scoring for genuinely non-empty inputs is completely
unchanged. The `ValueError` for a mismatched corpus should be raised *before*
any scoring happens, and its message must say that the number of reference
sets must match the number of hypotheses.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest nltk/test/unit/test_ribes.py -q -p no:cacheprovider
```

The existing RIBES test file is green at the pinned commit; keep it that way.
Add your own scratch tests under `/tmp` if that helps you verify. Note the
verifier requires the working tree inside the clone to contain exactly one
change, so the verdict on your fix is made by the verifier, which runs the
upstream regression tests and hidden cases its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that only the minimal tracked source is modified, and that no
  upstream fix was fetched into the clone.

## What the verifier checks

1. The tree is still at commit `a167389c027a02a9d1f019630ed827f4069b3353`,
   only the minimal tracked source file is modified, and the upstream fix
   commit was not pulled into the clone.
2. The upstream regression tests for this behaviour pass (they are extracted
   at image build time to `/opt/golden/test_ribes.py`).
3. The exact behaviour in the table above holds through the public API.
4. The project's own existing RIBES tests still pass.
5. Hidden cases over inputs the upstream tests do not use pass, including
   empty inputs of shapes the upstream tests never try, the exact error
   contract (a `ValueError` raised before any scoring, named reference sets in
   the message), and the guarantee that ordinary non-empty inputs still score
   exactly as before.

Deliverable: the repaired `/app/src` tree.