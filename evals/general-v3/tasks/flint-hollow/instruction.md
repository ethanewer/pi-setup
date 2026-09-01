# flint-hollow — Flintworks support-desk triage service

The **Flintworks** helpdesk wants a tiny deterministic HTTP triage service.
Your job is to implement a Flask app at `/app/app.py` and to run its
batch-classification mode to produce `/app/answer.json` for the visible
fixture. The service must work **on any request body** that follows the
contract below, not just the fixture.

## Environment

- Working directory: `/app`. It already contains `/app/visible_cases.json`
  (a JSON list of ticket texts). Python 3.12 and Flask are installed.
- No network access is needed at verify time; the service is only probed on
  localhost.

## Deliverables (both required)

1. `/app/app.py` — a runnable Flask program with this interface:
   ```
   python3 /app/app.py --serve [--port N]        # serve on 127.0.0.1 (default port 5000)
   python3 /app/app.py --classify-file IN OUT    # IN: JSON list of texts -> OUT: JSON list of results
   ```
   In `--serve` mode it must expose exactly two HTTP routes:

   - `POST /triage` — request body is JSON. Success returns HTTP **200** with
     a JSON body of the schema below (`Content-Type: application/json`).
   - `GET /health` — returns `{"ok": true}` with status 200.

2. `/app/answer.json` — the JSON list your program produces **when run in
   batch mode on the provided fixture**:
   ```
   python3 /app/app.py --classify-file /app/visible_cases.json /app/answer.json
   ```
   Each entry must be `{"text": <the input text>, "label": <str>,
   "confidence": {...}}` in the same order as the input list.

## POST /triage contract

Request: a JSON object with a `text` field that must be a **string**.

Response schema (status 200):

```json
{
  "label":      "<one of: urgent | normal | backlog>",
  "confidence": { "urgent": <float>, "normal": <float>, "backlog": <float> }
}
```

- `confidence` must contain **all three** classes as keys, every value a
  non-negative float rounded to **4 decimal places**, and the three values
  must sum to 1 (within rounding of ±0.002).
- `label` must be the class with the **largest confidence** (the argmax of
  the confidence object). If your confidences are computed correctly this
  holds automatically; a flipped or reordered confidence mapping will fail
  the grader.

Error responses (status **400**, JSON body `{"error": "<message>"}`):

- Body is not valid JSON, or is valid JSON but **not an object**:
  `{"error": "body must be valid JSON"}`
- Object without a `text` field, or with a non-string `text` (number, list,
  null, bool...): `{"error": "field 'text' must be a string"}`
- Extra keys in the object are allowed and ignored.

## Classification rules (deterministic — implement exactly)

1. Tokenize: lowercase the text, then extract maximal `[a-z0-9]+` runs.
   Punctuation and whitespace are separators. e.g. `"ASAP!!! this is
   CRITICAL!!"` → tokens `asap, this, is, critical`.
2. Count marker tokens per class:

   | class   | markers |
   |---------|---------|
   | urgent  | `asap, urgent, outage, critical, blocked, immediately, emergency` |
   | normal  | `update, review, question, draft, reminder, soon` |
   | backlog | `later, someday, eventually, whenever, backlog, deferred` |

   Tokens that match no marker list are ignored. Words that merely *contain*
   a marker (e.g. `urgency`, `ushers`) are **not** markers — only exact
   token matches count.
3. Score each class: `score(c) = 2 * count(c) + 1` (the `+1` keeps every
   class positive).
4. `confidence(c) = round(score(c) / (score(urgent) + score(normal) +
   score(backlog)), 4)`.
5. `label` = the class with the highest score. **Tie-break priority order:
   urgent, then normal, then backlog.** (All-zero counts is a 3-way tie →
   `urgent` with all confidences `0.3333`.)

Worked example: `"Major outage in production, we are blocked"` → counts
urgent=2 → scores urgent=5, normal=1, backlog=1, total=7 →
`{"label": "urgent", "confidence": {"urgent": 0.7143, "normal": 0.1429,
"backlog": 0.1429}}`.

## Edge cases the grader probes (hidden requests follow the same contract)

- All-zero counts (no markers, or empty string `""`) → 3-way tie → label
  `urgent`, every confidence `0.3333`.
- Two classes tied on score → tie-break priority (e.g. one urgent and one
  normal marker → `urgent`).
- Repeated markers all count (e.g. three `blocked` → count 3).
- Uppercase and punctuation-wrapped markers still count.
- Near-marker words (`urgency`, `ushers`, `eventual`, `wait`) do **not**
  count.
- Malformed requests: missing `text`, non-string `text`, non-object body,
  syntactically invalid JSON — each must return the exact 400 body above.

## Constraints

- The grader starts your app (`python3 /app/app.py --serve --port <N>`) and
  POSTs both the visible cases and hidden cases to it, then re-runs
  `--classify-file` on the visible fixture and compares with
  `/app/answer.json`. Do not hard-code the fixture texts.
- Batch mode input is always a JSON list of strings.
- Standard library + Flask only; no other third-party packages, no network
  calls from the app itself.
- Do not modify `/app/visible_cases.json`.
