# Batch document triage: OCR and text-extract a mixed batch into categories

`/app/inbox/` contains **12 business documents** (6 PDFs + 6 PNG raster
images). Each document is one of three kinds: **invoice**, **receipt**, or
**memo**. Each document body contains exactly one machine-readable label —
one of the uppercase words `INVOICE`, `RECEIPT`, `MEMO` — which tells you its
kind. The filename does NOT reliably tell you the kind, so you must read the
actual document content.

## Your objective

Build a robust **batch pipeline** that, for every input document, extracts its
text, classifies it to one of the three kinds, and routes (**copies**) it into
an output folder by kind, preserving the original filename:

```
/app/out/invoice/<name>
/app/out/receipt/<name>
/app/out/memo/<name>
```

- PDFs have an embedded text layer: extract text with `pypdf` (the pages were
  produced by a report generator; the label appears as text on page 1).
- Raster images are photographs of typed labels: OCR them with `pytesseract`
  (the underlying `tesseract` engine is installed). Each image is a clean,
  white-background rendering of a single uppercase label, so OCR should be
  reliable.
- Use the **first** label word found in the extracted text as the class. Map
  `INVOICE -> invoice`, `RECEIPT -> receipt`, `MEMO -> memo`. There is exactly
  one label per document.
- Every input document must end up in **exactly one** category folder. Do not
  drop any, and do not put the same file in two folders. Leave originals in
  `/app/inbox/` untouched.

## Deliverables

- `/app/classify.py` — the pipeline script.
- `/app/out/invoice/`, `/app/out/receipt/`, `/app/out/memo/` — populated with
  the classified copies (12 files total, one per input).

Suggested structure (pseudocode):

```python
import os, shutil
from pypdf import PdfReader
import pytesseract, PIL.Image

LABEL_DIR = {'INVOICE': 'invoice', 'RECEIPT': 'receipt', 'MEMO': 'memo'}

def extract_text(path):
    if path.lower().endswith('.pdf'):
        return '\n'.join(p.extract_text() or '' for p in PdfReader(path).pages)
    return pytesseract.image_to_string(PIL.Image.open(path))

for name in sorted(os.listdir('/app/inbox')):
    text = extract_text('/app/inbox/' + name).upper()
    label = next(k for k in LABEL_DIR if k in text)
    dst = '/app/out/%s/%s' % (LABEL_DIR[label], name)
    shutil.copyfile('/app/inbox/' + name, dst)
```

Run `python3 /app/classify.py`. Confirm a quick classification census counts
exactly 12 files across the three output folders, and that every
`/app/inbox` file has a counterpart in exactly one category folder.

## Verifier (what will be checked)

For each original file in `/app/inbox/`, the verifier independently re-extracts
its text the same way and recomputes the expected category, then verifies that
the file exists under the correct `/app/out/<category>/` folder; it also checks
that no file is duplicated across folders and that the total output count is 12.