# tl-ember-tangle — fix the race condition in the word-count service

The container runs an asyncio **word-count aggregation service** with a
deliberately seeded **race condition**. Requests to the service tally the
words of corpus documents into one shared running-count dict. Under
concurrent load the service **loses increments** (non-atomic read-modify-write
across an await), so the final counts undercount. Your job: write a precise
root-cause diagnosis and repair the service so the aggregation is exact under
the documented concurrent load — every run.

## Environment

| Path | What it is |
|---|---|
| `/app/svc/wordcount_service.py` | the service, **shipped with the seeded race** |
| `/app/svc/loadgen.py` | deterministic concurrent load generator |
| `/app/data/corpus.txt` | corpus: 50 documents, one per line (line *i* is document *i*, 0-based) |
| `/opt/pristine/` | byte-identical reference copies used ONLY by the grader — do not modify anything under `/opt` |

Python standard library only; no network beyond `127.0.0.1` loopback; keep
everything deterministic (no wall-clock or randomness as part of the answer).

## How the service works

Launch: `python3 /app/svc/wordcount_service.py --port PORT --corpus FILE`
(kernel prints one line `READY` on stdout once listening, then serves a
minimal HTTP-flavored protocol on `127.0.0.1:PORT`):

| Request line | Response body |
|---|---|
| `GET /req/<doc_id> HTTP/1.0` | `OK` — tallies document `<doc_id>` into shared counts |
| `GET /dump HTTP/1.0` | JSON object of the running counts |
| `GET /stop HTTP/1.0` | `BYE`, then the process exits 0 |

Responses are `HTTP/1.1 200 OK` with a `Content-Length` header.

**Tokenization rule (word = token, exact):** a document's text is read and
`text.lower().split()` applied; every resulting non-empty token contributes
`+1` per occurrence. Counts accumulate in a single in-memory dict shared by
all requests — parsing, spacing, or ordering of requests does not matter, only
the per-token totals.

## The load generator (deterministic schedule)

```
python3 /app/svc/loadgen.py \
    --service /app/svc/wordcount_service.py \
    --corpus /app/data/corpus.txt \
    --workers N --requests M --seed S --port P --out OUT.json
```

`loadgen` spawns the service as a subprocess, drives **N×M** requests through
N concurrent worker connections, dumps the final counts, stops the service,
and writes the counts JSON to `--out`. Schedule: with `rng =
random.Random(S)`, request index `k` (0 ≤ k < N×M) draws document
`rng.randrange(num_docs)`, where `num_docs` is the number of lines in the
corpus; worker `w` sends indices `w, w+N, w+2N, …`. Same arguments → same
schedule → same true counts. Exit code `0` only on full success; any failure
(service crash, protocol error, bad port, timeout) yields non-zero and no
valid `--out`.

## Reproduce the bug

1. **Ground truth (sequential ⇒ exact):** one worker serializes requests, so no
   two updates overlap and even the buggy service is exact:

   ```
   python3 /app/svc/loadgen.py --service /app/svc/wordcount_service.py --corpus /app/data/corpus.txt --workers 1 --requests 240 --seed 2718 --port 8642 --out /tmp/truth.json
   ```

2. **Documented load (concurrent ⇒ corruption):** 40 workers × 6 requests =
   240 requests, same seed, same total request set ⇒ the true counts are the
   same as step 1, but the race drops increments:

   ```
   python3 /app/svc/loadgen.py --service /app/svc/wordcount_service.py --corpus /app/data/corpus.txt --workers 40 --requests 6 --seed 2718 --port 8643 --out /tmp/buggy.json
   ```

   `diff /tmp/truth.json /tmp/buggy.json` shows the undercount. After your
   fix the 40-worker run must equal `/tmp/truth.json` **exactly, every run**.

## Deliverables (both required)

1. **`/app/diagnosis.md`** — the root-cause writeup. It must:
   - name the **exact line numbers** in the *shipped* file where the read of
     the shared dict entry, the `await` (simulated slow I/O step), and the
     write-back sit. Capture them *before* you edit — the shipped file is
     also preserved verbatim at `/opt/pristine/wordcount_service.py` with the
     same numbers;
   - describe the **interleaving** (which two requests, what stale value,
     which increment is lost);
   - state the **fix class** you applied and why it removes the race.

2. **`/app/svc/wordcount_service.py`** — repaired **in place**. Keep the CLI
   (`--port`, `--corpus`, `--io-latency`), the `READY` line, the protocol,
   the tokenization rule, and loopback-only behavior identical. A correct
   repair makes the merge into the shared dict atomic (one synchronous
   critical section, or an `asyncio.Lock`), keeping the simulated slow I/O
   step but never between a counter's read and its write-back.

## How the grader probes it

- It runs the fixed deliverable under the **documented load** (40 workers, 6
  requests, seed 2718, 240 requests) and independently recomputes the true
  counts from the corpus and the schedule rule above — exact equality
  required.
- It then **re-runs the ORIGINAL shipped service** (pristine bytes, from
  `/opt/pristine/`) under that same load and requires the counts to be
  **wrong** (corruption reproduces) — weakening the load or short-circuiting
  the run cannot help, because the grader supplies the load itself.
- It runs the fixed deliverable against **2-3 hidden corpus/load configs**
  (different worker counts and document sets) and independently recomputes
  expected counts for each — hardcoding the visible counts fails the hidden
  cases.
- It runs `loadgen` **unmodified from its own pristine copy**, not your
  `/app/svc/loadgen.py`; editing the load generator cannot help.
- It integrity-checks the fixtures (`/app/data/corpus.txt`,
  `/app/svc/loadgen.py`, and everything under `/opt/pristine/`) — leave them
  byte-identical.
- It reads `/app/diagnosis.md` and checks it names the exact read/await/write
  lines of the shipped original and states a valid fix class.

## Constraints

- Python stdlib only. No network beyond loopback. No GPU. Deterministic only.
- Modifying anything under `/opt` or the fixtures listed above fails grading.
- Keep the service responsive: the whole grader cycle must stay fast
  (the load above takes ~1 second per run when correct).