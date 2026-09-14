# chain-companion

You are inside a real open-source codebase: **NLTK** (`nltk/nltk`), the
Natural Language Toolkit, checked out at a pinned commit in `/app/src` (the
working tree starts clean). There is a bug in the package's tree parsing.
Your job is to find it, fix it in the working tree, and prove the fix with
the project's own test tooling. You are deliberately **not** told which file
or function to change: localising the bug is part of the task.

You are also required to write your **own** failing reproduction as a
deliverable (`/app/repro.py`), and to see it fail against the unpatched
parser *before* you change anything. You choose the concrete inputs; the
description below tells you what class of input is broken.

## Environment

- Python 3.12 (single vCPU; `cpus = 1`). Installed and pinned: `numpy`,
  `pytest`, `pytest-mock`, `pyyaml`, `regex`, `click`, `tqdm`, `joblib`,
  `defusedxml`.
- `nltk` is installed *editable* from `/app/src`: the code in that checkout is
  exactly what `import nltk` loads. The checkout is shallow (one commit) and
  detached — do **not** commit, fetch, or otherwise modify `.git`.
- **There is no network** in this container; everything the build and the
  tests need is already baked in.
- Put any scratch files in `/tmp`, never inside `/app/src`.

## The bug (user-visible symptom)

`nltk.tree.Tree.fromstring` parses trees written in the standard
"labelled-bracket" notation, e.g.

```python
>>> from nltk.tree import Tree
>>> Tree.fromstring("(S (NP the cat) (VP sat))")
```

and `str(tree)` serialises a `Tree` back to that notation. Users report that
**any tree whose text contains a parenthesis escaped with a backslash** is
broken. A backslash-escaped `(` or `)` is meant to be a **literal character**
of the node label or leaf that contains it (a realistic trigger is a smiley
stored as a leaf, e.g. the two characters `:` then `\)`). Instead, on some
inputs the parser raises a `Tree.read():` `ValueError` while parsing, and on
others it does not raise but **silently mis-parses** — the escaped
parenthesis is treated as a structural bracket, so the tree is corrupted and
`str(tree)` never reproduces the source string. In both cases the input never
round-trips.

Correct behaviour: a backslash-escaped `(` or `)` is a literal character of
the node label or leaf that contains it, preserved exactly — parsing such a
tree and printing it must reproduce the source string byte-for-byte.

## Requirements

1. Write `/app/repro.py` — your own standalone reproduction of the bug. It
   must:
   - import `nltk.tree.Tree` and drive the parser through `Tree.fromstring`;
   - cover **at least** these three distinct failure shapes (choose your own
     concrete source strings): an escaped close parenthesis as the text of a
     leaf; an escaped open parenthesis as the text of a leaf; and an escaped
     close parenthesis directly after a colon, i.e. a smiley `:\)`, inside a
     leaf;
   - for each, assert that it round-trips exactly (`str(parsed) == source`)
     and that each escaped bracket lands in the tree as literal text (check
     `leaves()` / the labels);
   - exit code 0 if and only if every assertion holds, non-zero otherwise;
   - be self-contained: no command-line arguments, no input files.
   The script must **fail (non-zero) when run against the unpatched parser**
   and **pass when run against your fixed parser**. Verify both directions
   yourself: run it *before* fixing anything (it must fail), then again after
   you fix.
2. Fix the tree so that `python3 /app/repro.py` exits 0, and so that a label
   containing an escaped open bracket also parses correctly: for a tree whose
   child label is the two characters `\(` (a literal escaped open bracket)
   holding a single leaf, `Tree.fromstring` must yield that child with label
   `\(` and leaves `["x"]`.
3. Fix the mechanism, not just your specific strings: the same defect is
   reachable from other inputs (escaped brackets inside nested leaves and
   labels, and other bracket pairs). Do not catch the error around the call,
   do not disable the failing path, and do not special-case inputs.
4. Normal parsing (no escaped brackets) must be completely unchanged. Run
   the project's own existing test suite targeted at tree handling (below);
   it must stay green.
5. Scope: the final tree must be byte-identical to the pinned commit except
   for the **single source file where the bug lives**. The grader compares
   the bytes of every tracked file against the pinned commit's own blobs, so
   no cosmetic changes, no added/renamed/deleted files, no scratch files
   left behind inside `/app/src`, and no commits.

## Deliverables

1. `/app/repro.py` — your own reproduction (see Requirements 1).
2. `/app/src` — the repository with your fix applied in the working tree.

## Working loop (recommended)

1. **Reproduce.** Write `/app/repro.py` first, then run
   `python3 /app/repro.py` and watch it fail against the unpatched parser.
   Record what you see.
2. **Localise.** Study `Tree.fromstring` in the installed package: how the
   input string is broken into tokens (node labels, leaves, brackets), and
   where a backslash-escaped bracket currently goes wrong — both for the
   raising inputs and for the silently-misparsed ones.
3. **Fix** with the smallest possible change, then re-run
   `python3 /app/repro.py` — it must exit 0, and a label holding a literal
   escaped open bracket (child label `\(`, one leaf `x`) must parse to that
   structure.
4. **Prove nothing else broke:**
   ```bash
   cd /app/src
   python3 -m pytest -q -p no:cacheprovider nltk/test/unit/test_treetransforms.py
   ```
   (passes 5/5 on the pristine tree; must still pass with your fix).
5. Make sure `/app/repro.py` and `/app/src` are your only artifacts under
   `/app`.

## Grading

The verifier (the container's `/tests`) will, on your final tree:

- assert `HEAD` is still the pinned parent commit; assert every tracked file
  except the single source file where the bug lives is byte-identical to
  that commit; assert there are no untracked files;
- require `/app/repro.py` to exist;
- run your reproduction against your repaired tree — it must exit 0;
- run your reproduction against a **pristine pre-fix snapshot** of the
  package extracted from the pinned commit — it must exit non-zero (proves
  your reproduction is genuine and not hardcoded);
- run the project's own regression test for this bug, baked into the image at
  `/opt/golden/test_tree_golden.py` (upstream added it with the fix; it does
  not exist in your tree) — all 4 tests must pass;
- run `nltk/test/unit/test_treetransforms.py` — all 5 tests must pass;
- run hidden inputs that reach the same code path from inputs the upstream
  regression test does **not** use (escaped brackets in nested leaves and
  labels; a custom bracket pair) — each must parse and round-trip.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.
