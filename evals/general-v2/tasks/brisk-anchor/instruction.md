# brisk-anchor — Brinegrove Freight document-intelligence bench

**Brinegrove Freight Co.** receives scanned and plain-text documents, maps form
fields onto shipment-dossier facts via retrieval, reads rendered chess-board
states, and pulls profile facts out of free-text documents. You will author
four small, *reusable* Python programs under `/app`, run each one so it writes
the required JSON reports, and make every program general enough to be re-run
by the grader on **fresh unseen inputs** (passed as command-line arguments)
that probe different fonts, densities, layouts and edge/malformed cases.

All four programs are executed by the grader on the shipped `/app` fixtures and
again on hidden input directories. Each program therefore *must* accept the
input/output arguments documented below; do not hard-code file names.

Work only inside `/app`. Do not modify the shipped fixtures (the scans, fields,
chunks, boards and docs), only read them and write your programs + JSON reports.

---

## Deliverables

| Deliverable            | Purpose                                             |
|------------------------|-----------------------------------------------------|
| `/app/ocr.py`          | OCR scans and label each document invoice / other.  |
| `/app/invoice-labels.json` | report written by running `ocr.py`.            |
| `/app/field-map.py`    | TF-IDF retrieval mapping fields to chunks + stats.  |
| `/app/field-map.json`  | per-field best chunk mapping (written by program).  |
| `/app/retrieval-stats.json` | retrieval statistics (written by program).     |
| `/app/chess-read.py`   | read a board image into a structured position.      |
| `/app/positions.json`  | board positions (written by program).               |
| `/app/extract.py`      | regex extraction of profile facts.                  |
| `/app/profiles.json`   | extracted facts (written by program).               |

---

## 1. `ocr.py` — OCR + invoice-vs-other classification

Interface:
```
python3 /app/ocr.py [input_dir] [output_json]
```
- Default `input_dir` = `/app/scans`, default `output_json` = `/app/invoice-labels.json`.
- The input directory holds scanned documents as JPG, PNG and PDF files.
- For each file, produce its OCR text:
  - JPG/PNG: run `tesseract <image> stdout --psm 6` (use subprocess) and take stdout.
  - PDF: it is a *scanned* PDF (no embedded text). Rasterize the first page with
    poppler: `pdftoppm -png -r 150 -f 1 -l 1 <pdf> <prefix>` and OCR the resulting
    page-1 PNG with tesseract.
- Classification rule (the contract the grader checks):
  - document is **`invoice`** iff its OCR text satisfies **both**:
    - a case-insensitive word `INVOICE`: regex `\bINVOICE\b`,
    - a TOTAL figure: regex `\bTOTAL\b.{0,12}\d` (case-insensitive, dot-all).
  - otherwise it is **`other`**.
- Output JSON: an object `{ "<filename>": "invoice"|"other", ... }` keyed by the
  bare basename of each file (e.g. `"inv_round.jpg"`), **sorted by filename**.
- Edge cases you must handle: completely blank/whitespace scans (still `other`,
  never crash); a document with a TOTAL figure but no INVOICE word (→ `other`);
  a memo mentioning invoices but with no TOTAL figure (→ `other`); PDFs.

## 2. `field-map.py` — TF-IDF retrieval mapping + statistics

Interface:
```
python3 /app/field-map.py [-f FIELDS_DIR] [-c CHUNKS_DIR] [-m MAP_JSON] [-s STATS_JSON]
```
- Defaults: `-f /app/fields`, `-c /app/chunks`, `-m /app/field-map.json`,
  `-s /app/retrieval-stats.json`.
- Each of the two directories holds one `.txt` file per document: files in
  `chunks/` are shipment-dossier passages; files in `fields/` are form-field
  descriptions to be matched to a chunk.
- Algorithm (use `sklearn.feature_extraction.text.TfidfVectorizer()` with its
  **default** parameters):
  1. Read every `*.txt` in chunks (sorted by filename) → chunk corpus.
  2. `fit_transform` the chunk corpus to the TF-IDF matrix `C`.
  3. For each field file (sorted), transform its text to vector `f`.
  4. Cosine score between the field and every chunk = `C @ f`.
  5. **Best chunk** = argmax cosine. Ties are broken to the alphabetically
     lowest chunk filename.
  6. If a field's text contains **no tokens** (e.g. only whitespace or
     punctuation such as `... , ;`), it maps to chunk **`null`** with score
     `0.0` (still fully present in both outputs).
- Identifiers in the outputs are the file basename **without the `.txt`**
  suffix (e.g. `f_port`, `c04_port`).
- `field-map.json`: a JSON array `[ {"field": id, "chunk": id|null, "score": float} ]`
  sorted by `field`.
- `retrieval-stats.json`:
```
{
  "num_fields": <int>,
  "num_chunks": <int>,
  "per_field": {
     "<field>": {"best_chunk": id|null, "best_score": float,
                 "mean_score": float, "candidate_count": int,
                 "top_scores": [float,float,float]}
  },
  "aggregate": {"mean_best_score": float, "median_best_score": float}
}
```
  `top_scores` is the 3 highest cosine scores for that field, descending.
  Handle an empty fields dir gracefully (`num_fields` 0, empty per_field).

## 3. `chess-read.py` — read a rendered board into a structured position

Interface:
```
python3 /app/chess-read.py [input_dir] [output_json]
```
- Defaults: `input_dir` = `/app/boards`, `output_json` = `/app/positions.json`.
- Boards are machine-rendered PNGs with an exactly documented geometry and a
  fixed 12-colour piece palette (so a deterministic decoder reproduces the
  position exactly). Read the following rendering contract:

  - Image size **640 × 720**.
  - **Side-to-move indicator**: a filled disc of radius 16 centred at
    `(320, 34)`. Filled `(250,250,250)` ⇒ side `"w"` (white); filled
    `(24,24,32)` ⇒ side `"b"` (black).
  - **Board region**: x in `[0,640)`, y in `[70,710)`. It is an 8×8 grid of
    80px cells. Cell `(r,c)` (rank `r`, 0 = top = rank **8**; file `c`, 0 = file
    **a**) is centred at `(c*80+40, 70+r*80+40)`.
  - **Square colour** = light `(229,221,197)` when `(r+c)` is even, else dark
    `(148,138,84)`.
  - **Occupied squares**: the square holds the piece glyph filled with *one of
    the 12 palette colours*; an empty square shows only its square colour.
  - Palette (glyph fill colour ⇒ piece):
    ```
    white: K (255,250,240)  Q (188,232,255)  R (255,214,214)
           B (196,255,200)  N (230,214,255)  P (255,245,205)
    black: k (18,18,26)     q (94,38,140)    r (150,46,46)
           b (42,122,88)    n (28,92,168)    p (168,118,32)
    ```
- Decoder: sample the side-disc to get the side to move; for each of the 64
  cells sample the pixels in its central region, nearest-classify each sampled
  pixel against `{light, dark}` ∪ the 12 palette colours, and when a piece
  colour is present with solid backing use that piece, otherwise the square is
  empty.
- `positions.json`: a JSON array of entries
  `{"file": "<basename>", "placement": "<64 characters>", "side": "w"|"b"}`
  **sorted by file**. `placement` is the flat Rows-8-to-1 string: every rank is
  8 characters, `.` for an empty square, and uppercase letter = **white** piece,
  lowercase letter = **black** piece (e.g. the start position corresponds to
  `rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR`).

## 4. `extract.py` — regex profile-fact extraction

Interface:
```
python3 /app/extract.py [input_dir] [output_json]
```
- Defaults: `input_dir` = `/app/docs`, `output_json` = `/app/profiles.json`.
- The directory holds `.txt` profile documents. For each (sorted), extract the
  FIRST match of each pattern in the whole document; a missing field is `null`.
- Contracted. patterns (the grader recomputes these same patterns):
  - **name**: a labelled line `Name : content` or `Name = content`
    (label `Name` is case-insensitive) capturing 2–4 capitalised tokens on the
    **same line**:
    `\bName\s*[:=]\s*([A-Z][A-Za-z'.-]+(?:\s+[A-Z][A-Za-z'.-]+){1,3})`
    (match with the `re.IGNORECASE` flag; take capture group 1, stripped).
  - **email**: `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b`
  - **phone**: `((?:\+?\d{1,2}[\s-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4})`
    (group 1 = the whole match, preserved verbatim, e.g. `+1 206-448-3110`).
  - **zip**: `\b(\d{5}(?:-\d{4})?)\b`
- `profiles.json`: a JSON array of
  `{"doc": "<filename>", "name": str|null, "email": str|null, "phone": str|null, "zip": str|null}`
  **sorted by doc**.
- Edge cases the grader probes: documents with **no** Name line (→ `name` null);
  a malformed phone that must not extract (→ `phone` null); repeated/decoy
  email where the **first** occurrence wins; ZIP with optional `-9999` suffix.

---

## General notes

- Every program must be executable and called through `python3 /app/...` with
  the documented arguments, so the grader can re-run it on `/tests/hidden/...`.
- Build the JSON files by **running** your programs against the fixtures — the
  graders checks both the *programs* and the reports they produce, and then
  re-runs the programs on new inputs.
- Keep your output valid, well-formed UTF-8 JSON with the exact key/value shapes above.
- Your programs run in a container with `tesseract-ocr`, `poppler-utils`,
  `Pillow`, `numpy` and `scikit-learn` installed; external tool calls happen via
  `subprocess`.