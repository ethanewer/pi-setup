"""Build-time smoke check: the pinned parent commit must reproduce the bug.

Runs inside the task image build. If the parent commit does not crash
``displacy.render(..., jupyter=True)`` with the IPython>=9 ImportError, the
build fails closed instead of shipping a task whose oracle cannot pass.
"""
import IPython
import spacy
from spacy import displacy

assert IPython.__version__.startswith("9."), (
    f"IPython {IPython.__version__} does not trigger the bug (needs >=9)"
)
print(f"spacy {spacy.__version__}, ipython {IPython.__version__}")
assert spacy.__file__.startswith("/app/src/"), (
    f"spacy not importable from the editable checkout: {spacy.__file__}"
)

nlp = spacy.blank("en")
doc = nlp("Apple is looking at buying U.K. startup for $1 billion")
try:
    displacy.render(doc, style="ent", jupyter=True)
except ImportError as e:
    assert "display" in str(e), e
    print(f"SMOKE-OK: parent reproduces ImportError: {e}")
else:
    raise SystemExit("PARENT DID NOT REPRODUCE: render(jupyter=True) did not raise")