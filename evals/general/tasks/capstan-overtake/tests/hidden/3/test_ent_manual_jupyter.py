"""Hidden case 3: manual entity visualisation with jupyter=True.

Manual dict input (no Doc object at all) with a custom colour palette —
the golden test's entity path renders a real Doc with the default palette.
Same jupyter display branch; different input class and options.
"""
import IPython.display as ipy_display

from spacy import displacy

EXAMPLE = {
    "text": "Apple released the new iPhone today.",
    "ents": [
        {"start": 0, "end": 5, "label": "ORG"},
        {"start": 23, "end": 29, "label": "PRODUCT"},
    ],
}


def test_ent_manual_jupyter_payload_handed_to_ipython(monkeypatch):
    calls = []
    monkeypatch.setattr(
        ipy_display, "display",
        lambda obj=None, **kw: calls.append(obj) or None,
    )
    displacy.render(
        EXAMPLE,
        style="ent",
        manual=True,
        jupyter=True,
        options={"colors": {"ORG": "#547d77", "PRODUCT": "#7aecec"}},
    )
    assert len(calls) == 1, f"display was called {len(calls)} times, expected 1"
    payload = calls[0].data
    assert "Apple" in payload
    assert "iPhone" in payload
    assert "ORG" in payload
    assert "PRODUCT" in payload
    assert "#547d77" in payload
    assert "#7aecec" in payload