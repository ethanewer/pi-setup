#!/bin/bash
# Verifier for item-025-main: independently reclassify each inbox file from its
# content and confirm the result lives in exactly one /app/out/<category> folder.
mkdir -p /logs/verifier
reward=0

if [ -d /app/inbox ] && [ -d /app/out ]; then
  if python3 - <<'PYEOF'
import os, sys
from pypdf import PdfReader
import pytesseract
from PIL import Image

LABEL_DIR = {'INVOICE': 'invoice', 'RECEIPT': 'receipt', 'MEMO': 'memo'}

def extract_text(path):
    if path.lower().endswith('.pdf'):
        return '\n'.join((p.extract_text() or '') for p in PdfReader(path).pages)
    return pytesseract.image_to_string(Image.open(path))

inbox = '/app/inbox'
out = '/app/out'
names = sorted(os.listdir(inbox))
if len(names) != 12:
    print('expected 12 inputs, got', len(names))
    sys.exit(1)

# Recompute the expected category from each input's content.
expected = {}
for n in names:
    text = extract_text(os.path.join(inbox, n)).upper()
    label = next((k for k in LABEL_DIR if k in text), None)
    if label is None:
        print('no label found in', n)
        sys.exit(1)
    expected[n] = LABEL_DIR[label]

# Every file must be present under its expected category folder.
for n, cat in expected.items():
    if not os.path.isfile(os.path.join(out, cat, n)):
        print('missing', os.path.join(out, cat, n))
        sys.exit(1)

# No file may appear in more than one category, and all 12 must be routed.
seen = {}
for cat in ('invoice', 'receipt', 'memo'):
    p = os.path.join(out, cat)
    if not os.path.isdir(p):
        print('missing dir', p)
        sys.exit(1)
    for n in os.listdir(p):
        if n in seen:
            print('duplicate', n)
            sys.exit(1)
        seen[n] = cat

if set(seen) != set(expected):
    print('routing set mismatch')
    sys.exit(1)
if len(seen) != 12:
    print('expected 12 routed, got', len(seen))
    sys.exit(1)

print('all 12 documents correctly classified and routed')
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt