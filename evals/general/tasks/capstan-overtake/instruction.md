# Rendering annotation visualisations for Jupyter crashes with an ImportError

## Situation

`/app/src` is a shallow, pinned clone of the spaCy repository
(`https://github.com/explosion/spaCy`) at upstream commit
`f5d04868e1e66d0acd6417b1c8099bcd4068fff7`, checked out in detached HEAD.

The package is already installed in *editable* mode (`pip install -e .`), so
`import spacy` resolves the copy living in the checkout: any pure-Python edit
you make under `/app/src` is picked up immediately, with no rebuild or
reinstall step. The Cython extensions have been pre-compiled; nothing in this
task requires recompiling anything. There is **no network** at trial time:
`git fetch`, `pip install` and `curl` will all fail. Everything you need is
already installed, among others pytest 9.1.1 and IPython 9.17.1.

Your deliverable is the repaired repository at `/app/src`. Do not modify or
reinstall anything outside the checkout, and do not shuffle the git state of
the checkout (no commits, no branch switches, no resets).

## The bug

spaCy ships an HTML rendering helper (`spacy.displacy`) that Jupyter notebook
users call to draw annotation visualisations inline under a document:
named-entity spans, parse trees, or span underlines. Passing
`jupyter=True` asks the renderer to hand the produced markup to IPython for
display. (In a real notebook this is detected automatically; from plain
Python the flag must be passed explicitly.)

On this checkout, every `render(..., jupyter=True)` call **crashes** — before
anything is shown — with

```
ImportError: cannot import name 'display' from 'IPython.core.display'
```

The crash comes from spaCy's own rendering code, not from a missing package:
it imports its IPython display helper from a module path that this IPython
release (9.17.1) no longer provides. The plain non-notebook rendering paths
(all calls made *without* `jupyter=True`) work fine and must keep working.

## Reproduce

```
cd /app/src && python3 - <<'EOF'
import spacy
from spacy import displacy

nlp = spacy.blank("en")
doc = nlp("Apple is looking at buying U.K. startup for $1 billion")
html = displacy.render(doc, style="ent", jupyter=True)
print("RENDER-OK", type(html))
EOF
```

## Your task

Repair the checkout so that the notebook rendering workflow works again:
the `jupyter=True` code path must complete without raising, the annotation
markup must still be produced, and the result must still be handed to IPython
for display. Keep the plain rendering paths and the rest of the library
behaving exactly as they do now.

The project's own displaCy test module is the local regression check to keep
green:

```
cd /app/src && python3 -m pytest -q spacy/tests/test_displacy.py
```

It currently passes on the untouched checkout (it never exercises the
notebook path, which is why it does not catch the crash) and it must still
pass after your fix.

Work inside the checkout and leave the deliverable there: the verifier will
run the reproduction, additional notebook-path cases, and the project's own
test module against your repaired tree, and will check that the tree still
sits at the pinned upstream commit with only the fix itself changed.