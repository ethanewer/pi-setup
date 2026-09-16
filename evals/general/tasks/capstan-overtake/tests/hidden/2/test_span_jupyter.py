"""Hidden case 2: span-underlining visualisation with jupyter=True.

Uses the span renderer on a Doc annotated with a styled-spans dict — a
renderer the golden test does not touch — through the same jupyter display
branch of render().
"""
import IPython.display as ipy_display

import spacy
from spacy import displacy
from spacy.tokens import Span


def test_span_jupyter_payload_handed_to_ipython(monkeypatch):
    calls = []
    monkeypatch.setattr(
        ipy_display, "display",
        lambda obj=None, **kw: calls.append(obj) or None,
    )
    nlp = spacy.blank("en")
    doc = nlp("Welcome to the Bank of China in Beijing")
    doc.spans["sc"] = [Span(doc, 3, 6, "ORG"), Span(doc, 6, 7, "GPE")]
    displacy.render(doc, style="span", jupyter=True)
    assert len(calls) == 1, f"display was called {len(calls)} times, expected 1"
    payload = calls[0].data
    assert "Bank" in payload
    assert "China" in payload
    assert "ORG" in payload
    assert "GPE" in payload