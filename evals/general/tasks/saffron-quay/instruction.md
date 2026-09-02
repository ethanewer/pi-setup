# saffron-quay — Harborline review triage endpoint

The support team at **Harborline** needs a small HTTP triage service that
scores incoming customer review snippets. You will author one self-contained
Python program, `/app/server.py`, that provides both a **Flask** HTTP
endpoint and a batch scoring mode, and run it once to produce `/app/answer.json`.
The service must work on **any** text conforming to the contract below — not
just the provided file.

## Environment

- Working directory: `/app`. It already contains the input file
  `/app/reviews.txt` (one review per line). Python 3.12 and Flask are available.
- **Do not modify `/app/reviews.txt`.**

## Deliverables (both required)

1. `/app/server.py` — a runnable Python program with two CLI modes:
   ```
   python3 /app/server.py serve <port>              # start the HTTP service
   python3 /app/server.py score <input.txt> <out.json>   # batch scoring
   ```
2. `/app/answer.json` — the JSON array your program produces **when run in
   score mode on the provided `/app/reviews.txt`**:
   ```
   python3 /app/server.py score /app/reviews.txt /app/answer.json
   ```

## The classifier (fully specified)

- **Lexicons** (a word is matched on the lower-cased alphabetic token,
  exactly):
  - POSITIVE = `love excellent amazing delight superb flawless recommend perfect`
  - NEGATIVE = `hate terrible awful disaster broken refund angry disappointing`
- **Tokens**: `re.findall(r"[a-z]+", text.lower())`.
- Let `pos` / `neg` be the counts of token hits in each lexicon.
- **label**:
  - `pos > neg` → `"positive"`
  - `pos < neg` → `"negative"`
  - `pos == neg > 0` → `"mixed"`
  - otherwise → `"neutral"`
- **confidence**: add-one-smoothed relative frequencies over the three
  classes: `wp = pos + 1`, `wn = neg + 1`, `wu = 1`, `total = wp + wn + wu`,
  and
  ```json
  {"positive": round(wp/total, 6), "negative": round(wn/total, 6), "neutral": round(wu/total, 6)}
  ```
  The confidence object always has exactly the three keys `positive`,
  `negative`, `neutral` (the label `"mixed"` is not a confidence key).

## HTTP service (`serve <port>`)

Starts an HTTP server on `127.0.0.1:<port>` exposing:

- `GET /health` → HTTP 200 with JSON `{"status":"ok"}` (the grader polls this
  to detect readiness).
- `POST /score` — request handling, in order:
  1. `Content-Type` must be `application/json` (or `application/*+json`);
     anything else → HTTP **400** with JSON body `{"error":"bad-content-type"}`.
  2. The JSON body must parse to a mapping containing a **string** field
     `text`; if the body fails to parse, is not an object, or `text` is
     missing / not a string → HTTP **400** with `{"error":"missing-text"}`.
  3. Otherwise → HTTP **200** with the classification result:
     `{"label": <string>, "confidence": {"positive": <float>, "negative": <float>, "neutral": <float>}}`.

## Batch scoring (`score <input.txt> <out.json>`)

Read the input file line by line. Skip empty / whitespace-only lines. For
every remaining line (with the trailing newline stripped) append
`{"text": <line>, "label": ..., "confidence": {...}}` to a JSON **array**
written to the output path, in file order.

## Edge cases the grader probes (hidden)

- **Empty or whitespace-only text** → `pos = neg = 0` → label `"neutral"`,
  confidence `{"positive":0.333333,"negative":0.333333,"neutral":0.333333}`.
- **Ties**: exactly one positive and one negative hit → `"mixed"` with
  confidence `0.4 / 0.4 / 0.2`; digits-only or punctuation-only text →
  `"neutral"`.
- **Case and punctuation**: lexicon words are recognised regardless of case
  and surrounding punctuation (e.g. `SUPERB!!!` counts as a positive hit).
- **No hits at all** → `"neutral"`.
- **Non-JSON content type** (e.g. `text/plain`) → 400
  `{"error":"bad-content-type"}`.
- **JSON object without a string `text` field** (missing field, non-string
  value, or unparseable JSON body) → 400 `{"error":"missing-text"}`.

## Constraints

- No network access is needed beyond the local loopback server the grader
  starts; the grader launches `python3 /app/server.py serve <port>` itself and
  re-runs the score mode on hidden inputs, so do not hard-code the provided
  file contents.
- Do not modify `/app/reviews.txt` (its integrity is checked).
- Do not create or write anything under `/tests` (mounted read-only at verify
  time).
- Deterministic: the same text always yields the same result.
