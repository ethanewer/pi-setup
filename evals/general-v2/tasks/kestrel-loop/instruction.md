# Kestrel-loop — speculative draft-and-verify decoding

You are on the inference-optimization team at **Kestrel-loop**. A tiny two-model
stack (a *target* model and a cheaper *draft* model) ships as a single JSON
"dual-logits" file. Your job is to implement the **speculative draft-and-verify
loop** that accelerates decoding against a known reference continuation, and to
run it once on the shipped fixture.

Everything lives in `/app`. The shipped fixtures are:

- `/app/data/model.json` — the dual-logits model (see format below).
- `/app/spec_case.txt` — the visible case specification (see format below).

**Do not modify or move anything under `/app/data`, and do not modify
`/app/spec_case.txt`.** You may create other supporting files in `/app`, but you
MUST produce exactly the deliverables below. `python3` (standard library
only; there is no third-party package such as numpy) is available. There is
no network access.

---

## 1. The dual-logits model (`/app/data/model.json`)

JSON object:

```json
{
  "format": "kestrel-dual-logits-1",
  "vocab_size": 12,
  "tokens": ["k00", ...],            // V token labels (informational)
  "draft_logits": [[[ ... ]]],       // V x V x V floats
  "target_logits": [[[ ... ]]],      // V x V x V floats
  "target_bias": [ ... ]             // V floats
}
```

Both models predict a next token from the **last two tokens** `[a, b]` of the
current context:

```
draft score for i  = draft_logits[a][b][i]                 (no bias)
target score for i = target_logits[a][b][i] + target_bias[i]
next token = argmax over i, ties broken to the LOWEST index i
```

Implement the argmax yourself if you like — either way, ties must go to the
LOWEST index. Contexts are always at least 2 tokens long. Parse sizes from `vocab_size` — never hard-code 12: the
grader also runs your program on a **hidden model with a different
vocab_size and different values**.

## 2. Case specification file format

A case file is plain text with exactly four `key=value` lines (order fixed,
values trimmed):

```
model=/app/data/model.json
prefix=3,1
draft=3
target=9,1,5,0,1,4,3
```

- `model` : path to a dual-logits model file.
- `prefix` : comma-separated integer token ids, at least 2 — the starting
  context.
- `draft` : positive integer `K`, the draft block length.
- `target` : comma-separated integer ids — the reference continuation to verify
  against. It may be **empty** (the value may be an empty string, meaning zero
  target tokens).

## 3. Deliverable A — `/app/spec_loop.py`

A runnable Python program:

```
python3 /app/spec_loop.py --model <model.json> --prefix <a,b> --target <t1,t2,...> --draft K --out FILE
```

All five flags are required. `--prefix`/`--target` are comma-separated id
lists; `--target` given as an empty string means an empty target. `--draft` is
a positive integer. Write the result JSON to `FILE`.

### The draft-and-verify algorithm

Loop until the context has absorbed the full `prefix + target` (i.e. while
`len(context) < len(prefix) + len(target)`):

1. **Draft**: from the current context, propose a block of exactly `K` tokens
   using the draft model (greedy argmax over the last two tokens, feeding each
   proposal back into the context as you go). The block is always `K` tokens,
   regardless of how many target tokens remain.
2. **Verify**: compare the proposed tokens one-by-one to the target sequence at
   the same absolute positions (position `len(prefix)` is target index 0).
   Accept the run of matches **up to the first mismatch**, and never compare
   beyond the end of the target.
   - `accepted` = number of matched proposals before the first mismatch (or
     before target exhaustion).
   - `rejected` = true exactly when a mismatch occurred **before** the target
     was exhausted; if the block simply ran out of target to compare against
     (e.g. `K` exceeds the remaining target length and all remaining tokens
     matched), `rejected` is false and `accepted` equals the remaining target
     length.
3. **Extend**: append the accepted proposals to the context. If the block was
   rejected, additionally append the **target's token at the mismatch
   position** (the "corrected" verified token) and count one correction.
4. Repeat.

Every iteration appends at least one token, so the loop always terminates.

### Output JSON (exact keys)

```json
{
  "vocab_size": 12,
  "prefix": [3, 1],
  "target": [9, 1, 5, 0, 1, 4, 3],
  "draft_len": 3,
  "result": [3, 1, 9, 1, 5, 0, 1, 4, 3],
  "n_drafted": 15,
  "n_accepted": 3,
  "n_corrected": 4,
  "blocks": [
    {"start": 2, "draft": [9, 1, 5], "accepted": 3, "rejected": false},
    {"start": 5, "draft": [10, 1, 4], "accepted": 0, "rejected": true}
  ]
}
```

- `result` is always exactly `prefix + target` when the loop finishes.
- `n_drafted` = total proposed draft tokens = `K` per executed block.
- `n_accepted` = total draft tokens accepted into the context.
- `n_corrected` = number of mismatch-replacement tokens appended =
  `len(target) - n_accepted`.
- `blocks` is in loop order; `start` is the **absolute index** in the full
  sequence where the block began (`len(prefix)` for the first block).
- For an **empty target**: zero blocks are executed, `result` equals the
  prefix, and all three counters are `0`.

## 4. Deliverable B — `/app/spec_result.json`

Run your program on the shipped visible case and save its output:

```
python3 /app/spec_loop.py --model /app/data/model.json \
  --prefix 3,1 --draft 3 --target 9,1,5,0,1,4,3 --out /app/spec_result.json
```

(The exact visible arguments are also the ones in `/app/spec_case.txt`; keep
`/app/spec_result.json` in place after generating it.)

## 5. How you are graded

The verifier runs `/app/spec_loop.py` **unchanged** on the visible case and on
several hidden cases with different models (different `vocab_size` and
values), prefixes, targets, and `K` values, and compares your full output JSON
to a reference — including `result`, all three counters, and every `blocks`
entry (`start`, `draft`, `accepted`, `rejected`). Hidden cases probe, among
other things:

- `K = 1`.
- `K` **larger** than the remaining target length (overrun: accept exactly the
  remaining length, `rejected` false), including a mismatch after a partial
  match in that situation.
- a target that is exactly the **draft model's own greedy continuation** (every
  block fully accepted, no corrections).
- models whose logit rows contain **ties** (the argmax must go to the lowest
  index).
- an **empty target**.
- short targets (length 1–5) and mixed accept/reject runs.

Off-by-one errors in the acceptance comparison or in the context update change
the counters and block records and will fail the check. The verifier also
checks that `/app/data/model.json` and `/app/spec_case.txt` were not modified.

## Constraints

- Deterministic; no network at run or verify time; standard library + `numpy`
  only.
- Do not hard-code the visible fixture's numbers, vocab size, or paths beyond
  the CLI contract above.
