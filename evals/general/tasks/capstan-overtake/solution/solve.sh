#!/bin/bash
# Oracle for capstan-overtake: applies the minimal upstream fix to the spaCy
# checkout at /app/src (spacy/displacy/__init__.py imports the IPython display
# helper from the deprecated IPython.core.display module path; the fix moves
# that one import to the supported IPython.display module), then proves the
# reproduction now works. The verifier (mounted /tests) re-checks everything;
# the oracle itself runs only the project-internal, tree-local commands.
set -e

python3 /solution/fix_displacy.py /app/src/spacy/displacy/__init__.py

cd /app/src
python3 - <<'EOF'
import spacy
from spacy import displacy
from spacy.tokens import Span

nlp = spacy.blank("en")
doc = nlp("Apple is looking at buying U.K. startup for $1 billion")
doc.ents = [Span(doc, 0, 1, "ORG")]
displacy.render(doc, style="ent", jupyter=True)
payload = displacy._html["parsed"]
assert "Apple" in payload and "ORG" in payload, "renderer output missing entities"
print(f"ORACLE-OK: jupyter=True render works; markup produced ({len(payload)} bytes)")
EOF