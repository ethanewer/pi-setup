"""Regression test: displaCy render(..., jupyter=True) must work on IPython>=9.

Authored as the golden test for the capstan-overtake task, from the upstream
reproduction: the upstream fix commit 94d6be8a9b1dbecc92820bd7996cd8c75e186320
(spaCy issue #13876) shipped NO regression test, so this file is the authored
golden test that replaces it.

On the buggy parent commit every test here fails inside the render call with

    ImportError: cannot import name 'display' from 'IPython.core.display'

because the renderer imports the IPython display helper from the deprecated
IPython.core.display module path that IPython>=9 removed. With the fix in
place the jupyter=True code path completes, produces the annotation markup
and hands it to IPython for display.

This file lives in /opt/golden in the task image and is run by the task
verifier; it is not part of the agent's own test suite.
"""
import IPython.display as ipy_display

import spacy
from spacy import displacy
from spacy.tokens import Span


def make_doc():
    nlp = spacy.blank("en")
    doc = nlp("Apple is looking at buying U.K. startup for $1 billion")
    doc.ents = [Span(doc, 0, 1, "ORG")]
    return doc


def spy_display(monkeypatch):
    """Replace IPython's display() with a spy that records what the renderer
    asks IPython to show, proving the display path is actually wired up and
    not merely non-crashing."""
    calls = []

    def fake_display(obj=None, **kwargs):
        calls.append(obj)
        return None

    monkeypatch.setattr(ipy_display, "display", fake_display)
    return calls


def test_ent_jupyter_render_completes():
    doc = make_doc()
    displacy.render(doc, style="ent", jupyter=True)
    html = displacy._html["parsed"]
    assert "Apple" in html
    assert "ORG" in html


def test_ent_jupyter_payload_handed_to_ipython(monkeypatch):
    calls = spy_display(monkeypatch)
    doc = make_doc()
    displacy.render(doc, style="ent", jupyter=True)
    assert len(calls) == 1, f"display was called {len(calls)} times, expected 1"
    payload = calls[0].data
    assert 'class="tex2jax_ignore"' in payload
    assert "Apple" in payload
    assert "ORG" in payload