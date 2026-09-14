# A tokenizer bug: opening single quotes stick to the following word

## Environment

- A development checkout of the **NLTK** natural-language toolkit is at
  **`/app/src`**, installed in editable mode: `import nltk` and
  `from nltk.tokenize import NLTKWordTokenizer` load the code directly from
  `/app/src/nltk`, so an edit under `/app/src` takes effect immediately.
- The NLTK data bundles the tests need (`punkt_tab`, `punkt`, `words`) are
  already installed under `/nltk_data`. **Do not download anything and do not
  re-run `pip install`**; the environment is fully provisioned and the
  acceptance expects it unchanged.
- Everything here is pure Python and the machine is budgeted at one CPU.

## The bug

`nltk.word_tokenize()` (and the tokenizer it delegates to,
`NLTKWordTokenizer`) mishandles an **opening single quote** when it is
followed by a word longer than one letter. Two user-visible symptoms:

1. The opening quote stays glued to the word: `'hello'` tokenises as
   `["'hello", "'"]` instead of `["'", "hello", "'"]`, and `'Hard'` becomes
   `["'Hard", "'"]` so a quoted word is never a clean token.
2. Some words are split apart instead: `'tis` (as in `'tis a fine day`)
   tokenises as `["'t", "is", ...]`, ripping the word in two.

Words that legitimately contain apostrophes must keep working: `o'clock`
must stay a single token, `O'Connor` must stay a single token, and
contractions like `'re`, `'s`, `'ll` (e.g. `they're`, `it's`) must keep
splitting as they do today.

Quoted short words already behave (a single-letter quoted word like `'a'` is
fine) -- it is the multi-letter case that is broken, plus the mid-word split
of a few short forms.

## What you must deliver

1. **`/app/reproduce.py`** -- *your own* reproducible demonstration of the
   bug. Write it before fixing anything. It must use the checkout's
   tokenizer (`from nltk.tokenize import NLTKWordTokenizer` and/or
   `nltk.word_tokenize`) and **assert the correct, expected tokens** for at
   least three distinct quoted phrases: a multi-letter quoted word in a
   normal sentence, a multi-letter quoted word that starts the text, and one
   phrase containing a contraction or an intra-word apostrophe that must stay
   whole. Written this way the script **fails on today's code** (that is the
   point of a reproduction) and must **pass once the behavior is fixed**.
   Keep every assertion strict: assert the exact token list, e.g.
   `assert toks == ["'", "hello", "'"], toks`.

   The accepted solution must satisfy the acceptance in both directions for
   this file: it must fail when the run against the original, unfixed code,
   and pass when run against your repaired checkout. So make the assertions
   describe the correct behavior, not today's output.

2. **A fixed `/app/src` tree.** The user-visible behavior above must be
   fixed in the checkout itself, the project's own tokenizer test suite must
   still pass, and the repository must otherwise be untouched: the **only**
   change under `/app/src` may be the tokenizer's own source. Do not add,
   rename or delete any other tracked or untracked file in the repository,
   do not change the committed revision, and do not touch tests, data files
   or configuration (including `.git` files). Use `/tmp` for scratch files.

## Acceptance

The acceptance runs, against your repaired tree:

1. **your `/app/reproduce.py`** in both directions -- once against the
   original, unfixed code (it must fail there) and once against the repaired
   checkout (it must pass);
2. **the project's own regression test for this exact bug**, extracted from
   the upstream fix and run through the project's own pytest;
3. **the project's own existing tokenizer suite**
   (`/app/src/nltk/test/unit/test_tokenize.py`, all of it) to prove nothing
   else broke;
4. **its own hidden cases**, which exercise the same quote-padding behavior
   from inputs the regression test does not use.

Where in the tree the fix belongs and how exactly the rule is repaired are
**your call** -- the source, the test suite and the `git` history inside
`/app/src` are there for you to inspect. You are expected to reproduce the
symptom, locate the mistake and fix it for real; patching site-packages,
`/opt`, the interpreter, or anything outside `/app/src` does not count.

## Deliverable summary

- `/app/reproduce.py` -- your own failing-then-passing reproduction.
- The fixed `/app/src` tree -- bug gone, its own suite green, nothing else
  modified.
- Nothing else.