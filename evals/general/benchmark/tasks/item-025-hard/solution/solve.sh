#!/bin/bash
# Oracle solution for item-025 (OCR batch document pipeline).
set -euo pipefail

# A correct, robust pipeline implementation. Rewrites /app/pipeline.py with a
# route-every-input implementation and runs it, then self-checks with the
# supplied evaluator.
cat > /app/pipeline.py <<'PY'
#!/usr/bin/env python3
"""Robust batch document pipeline: mixed formats -> OCR/PDF text -> class ->
filesystem move, with a report and an every-input-has-exactly-one-destination
guarantee."""
import json
import os
import sys

import pymupdf
from PIL import Image
import pytesseract

pytesseract.pytesseract.tesseract_cmd = 'tesseract'

INBOX = '/app/inbox'
PROCESSED = '/app/processed'
REPORT = '/app/processed/report.json'
IMG_EXTS = ('.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff')


def ocr(img):
    return pytesseract.image_to_string(img, lang='eng')


def read_doc(path):
    """Return (text, method). method is 'pdf_text' when a text layer is used,
    'ocr' when OCR was required, and '' for unreadable/unsupported files."""
    low = path.lower()
    if low.endswith('.pdf'):
        doc = pymupdf.open(path)
        try:
            text = ''
            page_text = 0
            for page in doc:
                t = page.get_text().strip()
                if t:
                    page_text += 1
                    text += t + '\n'
                else:
                    pix = page.get_pixmap(dpi=150)
                    img = Image.frombytes('RGB', (pix.width, pix.height), pix.samples)
                    text += ocr(img) + '\n'
            if page_text:
                return text, 'pdf_text'
            return text, 'ocr'
        finally:
            doc.close()
    if low.endswith(IMG_EXTS):
        try:
            with Image.open(path) as img:
                return ocr(img.convert('RGB')), 'ocr'
        except Exception:
            return '', 'unknown'
    return '', 'unknown'


def classify(text):
    t = text.upper()
    if 'INVOICE' in t:
        return 'invoices'
    if 'RECEIPT' in t:
        return 'receipts'
    return 'unknown'


def main():
    if not os.path.isdir(INBOX):
        sys.exit('inbox missing')
    for sub in ('invoices', 'receipts', 'unknown'):
        os.makedirs(os.path.join(PROCESSED, sub), exist_ok=True)
    names = sorted(f for f in os.listdir(INBOX) if os.path.isfile(os.path.join(INBOX, f)))
    records = []
    for fn in names:
        src = os.path.join(INBOX, fn)
        text, method = read_doc(src)
        folder = classify(text)
        if method == 'unknown':
            folder = 'unknown'
            method = 'unknown'
        dst = os.path.join(PROCESSED, folder, fn)
        os.replace(src, dst)
        records.append({'source': fn, 'destination': folder, 'method': method})
    with open(REPORT, 'w') as f:
        json.dump({'generated': True, 'count': len(records), 'records': records}, f, indent=2)


if __name__ == '__main__':
    main()
PY

python3 /app/pipeline.py

# Run the supplied evaluator to confirm consistency.
python3 /app/evaluate.py

echo "SOLVED"