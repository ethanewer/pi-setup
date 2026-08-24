#!/bin/bash
set -euo pipefail

# Oracle solution for item-025-main: batch OCR/PDF classification pipeline.
mkdir -p /app/out/invoice /app/out/receipt /app/out/memo

cat > /app/classify.py <<'PYEOF'
import os, shutil
from pypdf import PdfReader
import pytesseract
from PIL import Image

LABEL_DIR = {'INVOICE': 'invoice', 'RECEIPT': 'receipt', 'MEMO': 'memo'}

def extract_text(path):
    if path.lower().endswith('.pdf'):
        return '\n'.join((p.extract_text() or '') for p in PdfReader(path).pages)
    return pytesseract.image_to_string(Image.open(path))

for name in sorted(os.listdir('/app/inbox')):
    text = extract_text('/app/inbox/' + name).upper()
    label = next(k for k in LABEL_DIR if k in text)
    shutil.copyfile('/app/inbox/' + name, '/app/out/%s/%s' % (LABEL_DIR[label], name))
PYEOF

python3 /app/classify.py

# sanity: exactly 12 output files, one per input, none duplicated
count=0
for d in invoice receipt memo; do
  count=$((count + $(find "/app/out/$d" -type f | wc -l)))
done
if [ "$count" != "12" ]; then
  echo "unexpected total output count: $count" >&2
  exit 1
fi
echo "classify.py ran; 12 files routed"