"""Hidden case 1: dependency-parse visualisation with jupyter=True.

A different visualiser (style="dep") than the golden test's entity renderer
and a different input (an explicitly annotated Doc built from the vocab with
deps/heads, no piped pipeline), exercising the same crashed code path: the
jupyter display branch of render().
"""
import IPython.display as ipy_display

import spacy
from spacy import displacy
from spacy.tokens import Doc

WORDS = ["Apple", "is", "looking", "at", "buying", "U.K.", "startup", "there"]
DEPS = ["nsubj", "aux", "ROOT", "prep", "pcomp", "dobj", "dep", "advmod"]
HEADS = [2, 2, 2, 3, 2, 4, 4, 2]


def make_dep_doc():
    nlp = spacy.blank("en")
    return Doc(nlp.vocab, words=WORDS, deps=DEPS, heads=HEADS)


def test_dep_jupyter_payload_handed_to_ipython(monkeypatch):
    calls = []
    monkeypatch.setattr(
        ipy_display, "display",
        lambda obj=None, **kw: calls.append(obj) or None,
    )
    displacy.render(make_dep_doc(), style="dep", jupyter=True)
    assert len(calls) == 1, f"display was called {len(calls)} times, expected 1"
    payload = calls[0].data
    assert "Apple" in payload
    assert "U.K." in payload
    assert "nsubj" in payload
    assert "dobj" in payload
    assert "looking" in payload