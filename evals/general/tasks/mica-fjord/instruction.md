# Mica-Fjord vocabulary serialization for the station release

The Mica-Fjord weather-station pipeline ships a frozen embedding matrix and
needs a matching **pickled vocabulary object**. Your job is to build the
vocabulary from the station telemetry corpus, keep its two maps exact inverses
of each other, size it exactly to the embedding rows, and serialize it so it
unpickles inside the release verifier (which only knows the class
`station_vocab.Vocab`).

Everything runs in `/app` with Python 3.12. `numpy` is installed. No network.

## Provided files (do NOT modify or delete)

- `/app/station_vocab.py` — the shipping `Vocab` dataclass (fields
  `word2idx: dict[str, int]`, `idx2word: dict[int, str]`, plus helpers
  `check_inverse()`, `size()`, `encode()`, `decode()`). **Import `Vocab` from
  this module and pickle an instance of it.** A vocabulary pickled from any
  other class (including a copy of the class defined in your own module)
  cannot be unpickled by the release verifier and will be rejected.
- `/app/data/telemetry_corpus.txt` — free text, one or more lines.
- `/app/embeddings.npy` — a `numpy` array of shape `(V, 16)`; `V` is the exact
  vocabulary size the release expects.

## Deliverables (all three required)

1. `/app/build_vocab.py` — a reusable CLI program:
   ```
   python3 /app/build_vocab.py <corpus.txt> <embeddings.npy> <out_pkl> <out_report.json>
   ```
   It must work on **any** corpus / embedding matrix conforming to the rules
   below, not only the provided files.

2. `/app/vocab.pkl` — the pickled `station_vocab.Vocab` instance produced by
   running your program on the provided fixtures:
   ```
   python3 /app/build_vocab.py /app/data/telemetry_corpus.txt /app/embeddings.npy /app/vocab.pkl /app/vocab_report.json
   ```

3. `/app/vocab_report.json` — the report written by that same run (see format
   below).

## Vocabulary construction rule (implement exactly)

1. Read the whole corpus file as UTF-8 text. Tokens are
   `re.findall(r"[a-z0-9]+", text.lower())` — lowercased alphanumeric runs;
   punctuation, underscores and whitespace are separators; case is folded.
2. Count token frequencies. A token is a **candidate** iff its frequency is
   `>= 2` (min-frequency 2).
3. Let `V` = number of rows of the embeddings array (`embeddings.shape[0]`).
   The vocabulary must have **exactly `V` entries**.
4. Reserve the two special tokens first: index 0 = `"<pad>"`, index 1 =
   `"<unk>"` (always present, always at these indices).
5. Sort the candidates by descending frequency, breaking ties by ascending
   token (plain string `<` ordering). Take the first `V - 2` of them and assign
   indices `2, 3, 4, ...` in that order.
6. If there are fewer than `V - 2` candidates, the request is unsatisfiable:
   print an error to **stderr** and **exit with a non-zero status**. Do not
   write the output files in that case.
7. Build `word2idx` as above and `idx2word` as its **exact inverse** (same
   key/value pairs, reversed). Both live in one pickled `station_vocab.Vocab`
   instance written to `<out_pkl>`.

## Report format (`<out_report.json>`)

Valid JSON with exactly these keys:

```json
{
  "vocab_size": 40,
  "embedding_rows": 40,
  "inverse_ok": true,
  "special_tokens": ["<pad>", "<unk>"],
  "first_regular": "anemo",
  "last_regular": "wharf"
}
```

- `vocab_size` and `embedding_rows` are equal integers (`V`).
- `inverse_ok` is the boolean result of calling `check_inverse()` on the built
  vocabulary (must be `true`).
- `first_regular` / `last_regular` are the first and last tokens from the
  ordered regular-token list (or `null` if there are none).

## Edge cases the verifier probes (hidden corpora)

- **Frequency ties** — many tokens sharing a frequency; the
  descending-frequency / ascending-token order must be respected exactly.
- **Case and punctuation** — `Baro,` `BARO` and `baro` are the same token;
  `station-42` yields token `42`; underscores/hyphens split tokens.
- **Exact fit** — a corpus whose candidate count equals `V - 2` precisely.
- **Unsatisfiable request** — a corpus with fewer than `V - 2` candidates:
  your program must exit non-zero, print something to stderr, and create
  **neither** output file.
- **Embedding-row consistency** — `vocab.size()` must equal
  `embeddings.shape[0]` in every feasible case; the two maps must satisfy
  `check_inverse()`.

## Constraints

- The verifier re-runs `/app/build_vocab.py` unchanged on hidden corpora and
  embedding matrices, so do not hard-code the provided file contents.
- Standard library + `numpy` only; deterministic; no network.
- Do not modify `/app/station_vocab.py`, `/app/data/telemetry_corpus.txt`, or
  `/app/embeddings.npy`.

## Checking your work

```bash
cd /app && python3 - <<'PY'
import pickle, numpy as np, station_vocab
v = pickle.load(open("/app/vocab.pkl", "rb"))
E = np.load("/app/embeddings.npy")
assert isinstance(v, station_vocab.Vocab)
assert v.check_inverse() and v.size() == E.shape[0]
print(v.decode(range(5)))
PY
```
