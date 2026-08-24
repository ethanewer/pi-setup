#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
from pypdf import PdfReader
r = PdfReader('/app/doc.pdf')
text = ''
for page in r.pages:
    text += page.extract_text() or ''
# normalize: collapse newlines/trailing whitespace
text = text.strip()
with open('/app/extracted.txt', 'w') as f:
    f.write(text + '\n')
print("wrote /app/extracted.txt")
PYEOF