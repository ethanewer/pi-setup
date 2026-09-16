"""Wrapper-free probe: the jupyter=True display path must work in the tree.

Run as ``python3 -S`` (no site processing) with the checkout root as argv[1].
With ``-S``, ``sitecustomize``, ``.pth`` files and user site are never
processed, so any wrapper an agent installs in site-packages to mask an
unfixed tree is inert here: the probe imports spaCy straight from the
checkout and exercises the exact upstream reproduction.

Exit 0 only if the render completes, actually hands the markup to
IPython.display.display (spy, without pytest), and the payload contains the
annotated text. Exit 1 otherwise, printing the observed ImportError.
"""
import site
import sys

if len(sys.argv) != 2:
    sys.exit("usage: python3 -S probe_jupyter_no_wrapper.py <checkout>")

checkout = sys.argv[1]
sys.path.insert(0, checkout)
# -S removed site-packages from sys.path; put it back so IPython (and any
# other library) imports, while sitecustomize/.pth stay unprocessed.
for p in site.getsitepackages():
    if p not in sys.path:
        sys.path.insert(0, p)

import IPython.display as ipy_display
import spacy
from spacy import displacy
from spacy.tokens import Span

calls = []
orig_display = ipy_display.display
ipy_display.display = lambda obj=None, **kw: calls.append(obj)

try:
    nlp = spacy.blank("en")
    doc = nlp("Apple is looking at buying U.K. startup for $1 billion")
    doc.ents = [Span(doc, 0, 1, "ORG")]
    displacy.render(doc, style="ent", jupyter=True)
except ImportError as e:
    print(f"PROBE-FAIL: render(jupyter=True) raised ImportError: {e}")
    sys.exit(1)

if len(calls) != 1:
    print(f"PROBE-FAIL: display was called {len(calls)} times, expected 1")
    sys.exit(1)

payload = getattr(calls[0], "data", "")
if "Apple" not in payload or "ORG" not in payload:
    print("PROBE-FAIL: display payload is missing the rendered annotation markup")
    sys.exit(1)

print("PROBE-OK: wrapper-free jupyter render works; markup handed to IPython.display")