# Stemming an empty string crashes the Hungarian Snowball stemmer

## Situation

`/app/src` is a shallow, pinned clone of the NLTK repository
(`https://github.com/nltk/nltk`) at upstream commit
`47e236e9505c6f552d6712a21c6d960879ba7f1e`, checked out in detached HEAD.
The NLTK package is installed **editable** from this tree (`pip install -e .`),
so any Python process you start in this container sees the sources under
`/app/src` exactly as they are on disk: change a source file and the very
next import picks the change up. There is no reinstall step.

Python 3.12 is installed with pytest 9.1.1, numpy 2.5.3 and the rest of
NLTK's runtime dependencies (click, joblib, regex, tqdm, defusedxml, pyyaml,
pytest-mock). Nothing needs to be downloaded: the stemmers are pure Python
and need no corpus data. Treat the environment as offline -- there is no
guaranteed network and no part of the task requires it. `git` is configured
(safe directory and a committer identity).

## The bug

A user reports that stemming an empty string with the **Hungarian** flavor
of NLTK's Snowball stemmer crashes:

```
>>> from nltk.stem.snowball import SnowballStemmer
>>> SnowballStemmer("hungarian").stem("")
Traceback (most recent call last):
  ...
IndexError: string index out of range
```

The traceback's last frame reads the first character of the word while
computing the word's *r1 region* (the region used by most of the Hungarian
suffix steps) and never checks whether the string is empty first. The user
stems token lists coming out of text-processing pipelines, and any empty
token kills the whole job.

Every other Snowball language NLTK ships (english, german, french, spanish,
russian, danish, dutch, italian, norwegian, portuguese, romanian, finnish,
swedish, arabic, porter) already handles `""` by returning `""` untouched.
The Hungarian flavor is the only one that crashes.

**Expected behaviour**: `SnowballStemmer("hungarian").stem("")` must simply
return `""`. Ordinary non-empty Hungarian words must still stem exactly as
they did before (e.g. `"sarki"` -> `"sar"`), and the other languages must be
unaffected.

## Your deliverables

Two things, both required.

### 1. `/app/reproduce.py` -- a reproduction script you write yourself

Write a standalone Python script at `/app/reproduce.py` that demonstrates
the bug and later proves it gone. It must:

- use NLTK's Snowball stemmer directly (`from nltk.stem.snowball import
  SnowballStemmer`);
- when the bug is present, fail: crash or exit with a non-zero status --
  **do not** catch the crash and turn it into a success;
- when the behaviour is correct -- `SnowballStemmer("hungarian").stem("")`
  returns `""` without raising -- print exactly one line
  `OK: empty string handled` and exit with status 0.

The verifier will run this script twice: once with the pristine, unfixed
tree (it must fail there -- that is what proves it is a genuine
reproduction of this bug, not a tautology) and once against your repaired
tree (it must exit 0 and print the marker line).

### 2. The repaired tree at `/app/src`

Fix the bug **in the checked-out tree** so the expected behaviour above
holds. Keep the change minimal and in place:

- stay at the pinned commit: do not commit, stage, reset, rewrite or fetch
  history, and do not add or change git remotes;
- change only the library source that the fix requires -- one library file
  -- and do not add, delete or rename any file in the repository;
- leave every file under `nltk/test/` untouched.

You may run any Python or pytest you like from `/tmp` (do not run pytest
with the repository as its root, so no cache files appear inside it).

## Harness-owned paths

`/opt/golden`, `/tests` and `/solution` belong to the harness. Do not read
or modify them.

## What the verifier checks

1. The tree is still at the pinned commit: exactly one commit reachable,
   the upstream history absent, and the only working-tree difference is a
   modification of the one library source file your fix requires.
2. The project's own regression test for this bug is run against your
   repaired tree and must pass for all sixteen Snowball languages.
3. A data-free subset of the project's existing stemmer tests must still
   pass, so your fix broke nothing else.
4. Hidden cases: your fix must keep ordinary Hungarian stemming intact
   (case, accents, digraphs), must leave whitespace/punctuation/digit
   inputs exactly as before, and must not disturb the other languages.
5. Your `/app/reproduce.py` is executed against a pristine pre-fix tree
   (must fail) and against your repaired tree (must print the marker and
   exit 0).