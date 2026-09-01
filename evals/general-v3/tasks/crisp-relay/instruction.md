# crisp-relay — Offline scorer with an immutable toolchain

You are inheriting the **mark-three** legacy batch text scorer. The platform
image ships a pinned ML toolchain that is **immutable**:

- `torch` version `2.13.0+cpu`
- `transformers` version `5.16.1`

A downstream offline consumer — the scorer itself — loads a saved model
through this exact toolchain from `/app/model_store`. **You may not upgrade,
downgrade, uninstall, or reinstall `torch` or `transformers`**, directly or as
a side effect of installing anything else. Altering them changes API
signatures and breaks the offline load path.

There is a trap lying around: `/app/vendor/requirements.txt` is a **stale
legacy pin file** left by the previous team. It lists two toolchain pins
(`torch==2.5.1`, `transformers==4.46.2`) alongside two vendor libraries.
Installing that file as-is would destroy the platform toolchain. The file
itself must stay in place (do not delete or edit it); just do not apply its
toolchain pins.

## Deliverables (all three required)

1. `/app/install_vendor.sh` — an **executable, idempotent** bash script that
   brings the two vendor helper libraries into the **system** Python **from
   the local wheelhouse only, with no network access**:

   - `/app/wheelhouse/toksplit-0.5.2-py3-none-any.whl` (package `toksplit`)
   - `/app/wheelhouse/textnorm-1.3.0-py3-none-any.whl` (package `textnorm`)

   After it runs, `python3 -c "import toksplit, textnorm"` must succeed
   system-wide with `toksplit.__version__ == "0.5.2"` and
   `textnorm.__version__ == "1.3.0"`, while `torch` and `transformers` remain
   at exactly `2.13.0+cpu` and `5.16.1`. The script must be safe to re-run
   (the verifier runs it again after you have already run it).

2. `/app/score.py` — a runnable Python program:

   ```
   python3 /app/score.py <input.txt> <output.json>
   ```

   It loads the saved model from `/app/model_store` **offline** with the
   pinned toolchain and writes the JSON described below. It must work on any
   input file conforming to the contract — not just `/app/inbox.txt`.

3. `/app/scores.json` — the output of your scorer **when run on the provided
   `/app/inbox.txt`**:
   ```
   python3 /app/score.py /app/inbox.txt /app/scores.json
   ```

## Scoring contract (implement exactly)

`score.py` reads a plain-text file, one document per line:

- A line that is empty after stripping surrounding whitespace is **ignored**.
- For every remaining line, compute a label:
  1. `norm = textnorm.normalize(line)`
  2. `tokens = toksplit.tokenize(norm)`
  3. `text = " ".join(tokens)`
  4. encode with the tokenizer loaded from `/app/model_store`:
     `tokenizer(text, truncation=True, max_length=16, return_tensors="pt")`
  5. run the model in inference mode; `label = int(logits.argmax())`
- Output: a JSON object `{"count": <number of scored docs>, "labels": [<0|1>, ...]}`
  in input order, written to the given output path. `count` equals `len(labels)`.

## Edge cases the grader probes with hidden inputs

- An **empty input file** → `{"count": 0, "labels": []}`.
- Input with only blank/whitespace lines → same as empty.
- Mixed-case and whitespace-padded documents (normalization must handle them).
- Documents with out-of-vocabulary words, duplicated lines, and lines longer
  than the model window (tokenization must truncate at `max_length=16`).
- Any number of documents; output must always have one label per kept line.

## Constraints

- **Do not** modify `/app/model_store`, `/app/wheelhouse`, `/app/vendor`,
  `/app/inbox.txt`, or anything else already in the image.
- **Do not** upgrade, downgrade, reinstall, or remove `torch` or
  `transformers` — not directly, not via `requirements.txt`, not as a
  dependency of anything you install.
- Everything must work **offline**: no network is available at run or verify
  time. The vendor wheels are already in `/app/wheelhouse`.
- The verifier re-runs `/app/install_vendor.sh` itself, so it must be
  idempotent and must finish quickly.
- Standard library plus the pinned toolchain plus the two vendor packages is
  all you should need.
