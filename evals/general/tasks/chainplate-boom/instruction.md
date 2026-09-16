# Chomsky normal form conversion crashes on trees that mix terminals with subtrees

## Situation

`/app/src` is a shallow, pinned clone of the NLTK natural-language toolkit
(`https://github.com/nltk/nltk`), checked out at upstream commit
`52227d2afe764648864e59c851e991cf1d6cb77e`, and installed from that tree in
editable (development) mode, so `import nltk` resolves to the checked-out
Python source and edits you make are picked up immediately. Python 3.12 is
installed together with numpy, pytest 8.4, pytest-mock, regex, pyyaml, click,
tqdm, joblib and defusedxml. There is **no network** at trial time:
everything you need is already in the image; `pip` and `git fetch` will not
work.

## The bug

The toolkit's normal-form conversion, exposed as
`chomsky_normal_form(tree, factor="right")` (both `"right"` and `"left"`
factorizations), rewrites a parse tree into Chomsky normal form: every node
ends up with at most two children, and the intermediate nodes are given
names that encode the original node label together with the labels of the
children they now dominate.

In this checkout the conversion crashes whenever an internal node with more
than two children has at least one **plain terminal** among those children —
a word, a punctuation mark such as `+`, or even a non-string value such as
the integer `7` — sitting alongside full subtrees. The binarization step
assumes every child is a subtree and reads a label from it, so it dies with
an `AttributeError`:

```
$ python3 -c "from nltk.tree import Tree; from nltk.tree.transforms import chomsky_normal_form; chomsky_normal_form(Tree.fromstring('(S (S 1) + (S 2))'), factor='right')"
AttributeError: 'str' object has no attribute 'label'
```

with a non-string terminal the same crash reads `'int' object has no
attribute 'label'`.

The intended behaviour is:

- converting any such tree must never crash, for both `factor="right"` and
  `factor="left"`;
- every node of the result must have at most two children;
- a terminal's own value is carried into the intermediate node names exactly
  the way a subtree's label would be;
- `un_chomsky_normal_form(result)` must give back the *exact* original tree;
- every tree that converted fine before must still convert to exactly the
  same result as before (same tree shape, same intermediate node names), so
  nothing that used to work changes.

## Reproducing the failure

```
python3 /app/probe_cnf.py
```

prints the failing cases. One-line confirmations of the same crash:

```
python3 -c "from nltk.tree import Tree; from nltk.tree.transforms import chomsky_normal_form; chomsky_normal_form(Tree.fromstring('(S (S 1) + (S 2))'), factor='right')"
python3 -c "from nltk.tree import Tree; from nltk.tree.transforms import chomsky_normal_form; chomsky_normal_form(Tree('S', [Tree('A',['a']), 7, Tree('B',['b']), Tree('C',['c'])]), factor='right')"
```

`un_chomsky_normal_form` is the inverse routine in the same module;
`Tree.subtrees()` yields every node of a tree, and `len(node)` the number of
its children.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that the intended
behaviour above holds for both `factor` directions. The fix must be minimal:
change only what the bug requires, in the same module the traceback points
into. Do not touch the test files, the packaging, or anything unrelated.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest nltk/test/unit/test_treetransforms.py -q -p no:cacheprovider
```

The existing tree-transform test file is green at the pinned commit; keep
it that way. Add your own scratch tests under `/tmp` if that helps you
verify. Note the verifier requires the working tree inside the clone to
contain exactly one change, so the verdict on your fix is made by the
verifier, which runs the upstream regression tests and hidden cases its own
way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that only the minimal tracked source file is modified, and that no
  upstream fix was fetched into the clone.

## What the verifier checks

1. The tree is still at commit `52227d2afe764648864e59c851e991cf1d6cb77e`,
   only the minimal tracked source file is modified, and the upstream fix
   commit was not pulled into the clone.
2. The upstream regression tests for this behaviour pass (they are extracted
   at image build time to `/opt/golden/test_treetransforms.py`).
3. The exact behaviour above holds through the public API.
4. The project's own existing tree-transform tests and doctests still pass.
5. Hidden cases over inputs and parameters the upstream tests do not use
   pass: other terminal shapes (floats, booleans, `None`, multi-symbol
   punctuation), nodes with more children than the upstream inputs, terminals
   nested deeper in the tree, and non-default `horzMarkov`/`vertMarkov`
   arguments — each with the exact round-trip contract.

Deliverable: the repaired `/app/src` tree.