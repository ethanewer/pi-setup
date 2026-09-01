# Route a Mixed Batch of Scanned Documents with OCR

`/app/inbox/` contains **8 documents of mixed formats** that arrived together:
some are real PDFs with an embedded text layer, some are scanned **raster images
(both PNG files and raster-only "scanned" PDFs)**, and one is junk binary that is
not readable. You must build a robust batch pipeline that classifies every
document and filesystem-**moves** each one into exactly one destination.

## The two document classes

Each readable document is exactly **one** of two classes, determined by the word
that appears prominently at the top of the document:

- **`invoices`** — documents whose extracted/OCR text contains the word
  **INVOICE** (reference numbers look like `INV-####`).
- **`receipts`** — documents whose extracted/OCR text contains the word
  **RECEIPT** (references look like `RCP-####`).

The input filenames (`doc-01.pdf` ... `doc-08.bin`) are **not** a reliable
source of the class; you must read each document's content to decide.

## Required end state (objective checks)

1. Move every input file into **exactly one** subdirectory under
   `/app/processed/`, keeping its **original basename**:
   - `/app/processed/invoices/<basename>` or
   - `/app/processed/receipts/<basename>` or
   - `/app/processed/unknown/<basename>` (for the one unreadable / non-document
     input that yields no text, `doc-08.bin`).
   No file may be left in the inbox, copied to two places, or dropped.

2. Write a JSON report to `/app/processed/report.json`:
   ```json
   {
     "generated": true,
     "count": 8,
     "records": [
       {"source": "doc-01.pdf", "destination": "invoices", "method": "pdf_text"},
       ...
     ]
   }
   ```
   One record per input, sorted by `source`, with `destination` in
   `{"invoices","receipts","unknown"}` and `method` describing how the class was
   determined (`"pdf_text"` when a PDF text layer was used, `"ocr"` when OCR was
   required, `"unknown"` when nothing was readable).

## How to read each format

- PDF with a text layer: use text extraction (e.g. `pymupdf` / `fitz`,
  `page.get_text()`); no OCR needed.
- Raster image (PNG/JPG/...): run OCR (`pytesseract` + the `tesseract` engine).
- **Raster-only PDF** (a PDF whose pages have no searchable text): render each
  page to an image and run OCR on it.
- Anything that still yields no text (e.g. `doc-08.bin`) is **unknown**.

## Files provided

- `/app/inbox/` — the 8 inputs (do not modify their contents).
- `/app/evaluate.py` — a **consistency evaluator** that checks exactly-one
  destination for every input and valid report structure. Run it as you work:
  ```
  python3 /app/evaluate.py
  ```
  It prints `CONSISTENT` when the pipeline is behaviorally correct, and lists
  issues otherwise. (It checks completeness, not classification; the final
  grader checks classification too.)

## Constraints

- The pipeline must **not** crash if one input is unreadable. A single bad
  document must never abort the whole batch.
- Do not use the inbox filenames to guess the class. Read content.
- All eight documents must be moved (every input gets exactly one destination).
  Leave nothing behind and place nothing twice.

Implement your pipeline (e.g. write `/app/pipeline.py`), run it, run the
evaluator, and confirm **both** a complete and correctly classified batch.