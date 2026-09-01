# Cedar Vault — deterministic archive-continuation generator

The Cedar Vault archive ships a small local "archive brain": a JSON model that
scores candidate next tokens for retrieval-query completions. You must write the
**greedy continuation generator** for it and run it on the shipped model.

There is **no network access**; Python 3.12 standard library only (numpy is not
required and not needed).

## The model file

A model file is JSON like the shipped `/app/model/lexicon.json`:

```json
{
  "name": "cedar-vault/archive-brain-v1",
  "vocab": ["tk00", "tk01", ...],     // V tokens, token id = index
  "dim": 4,                            // d = embedding dimension
  "ctx": 3,                            // context window size k
  "max_new": 6,                        // exact number of tokens to generate
  "default_prompt": [1, 3],            // prompt used when none is given
  "temperature": 0.8,                  // IGNORED (see below)
  "top_k": 3,                          // IGNORED
  "top_p": 0.9,                        // IGNORED
  "repetition_penalty": 1.25,          // IGNORED
  "embed": [[int,...], ...],           // V rows of d integers
  "head":  [[int,...], ...]            // d rows of V integers
}
```

## Greedy generation (the only accepted mode)

Generation is **greedy**: at every step the next token is the argmax of the
score, and **ties are broken to the lowest token id**. Do **not** apply
temperature, top-k, top-p, or any repetition penalty — those fields exist as
distractors and MUST be ignored. The generator never stops early: it appends
**exactly** `max_new` tokens (which may revisit tokens already present; there is
no end-of-sequence token).

Score of candidate token `i` given the sequence so far:

1. Take the **last `ctx` tokens** of the current sequence (or all of them if the
   sequence is shorter than `ctx`; an empty context never occurs — prompts have
   at least 1 token).
2. `score[i] = sum over context tokens t of sum over j of embed[t][j] * head[j][i]`

All values are integers, so scores are exact integers.
`next = argmax(score)` with the lowest id winning ties.

Worked example (2 tokens of context, d=1): if the context is `[a, b]` with
`embed[a] = [2]`, `embed[b] = [-1]`, and `head[0] = [3, 1, 1]`, then
`score = [2*3 + (-1)*3, 2*1 + (-1)*1, 2*1 + (-1)*1] = [3, 1, 1]` → next is
token 0. If instead `head[0] = [1, 4, 4]`, `score = [1, 4, 4]` → the max 4 is
shared by ids 1 and 2, so token **1** is chosen (lowest id on tie).

## Deliverables (both required)

1. `/app/generate.py` — a runnable Python 3 program:

   ```
   python3 /app/generate.py --model PATH [--prompt t1,t2,...] [--out FILE]
   ```

   - `--model` : path to a model JSON file (required).
   - `--prompt` : comma-separated integer token ids; overrides the model's
     `default_prompt`. All ids are guaranteed valid (0 <= id < V).
   - `--out` : output JSON path; default `/app/greedy.json`.

   It writes a JSON object with **exactly** these keys:

   ```json
   {
     "prompt": [int, ...],
     "max_new": <int>,          // copied from the model
     "continuation": [int, ...],  // exactly max_new ids
     "full": [int, ...]           // prompt + continuation
   }
   ```

2. `/app/greedy.json` — the output your program produces when run as

   ```
   python3 /app/generate.py --model /app/model/lexicon.json
   ```

   (i.e. on the shipped model with its default prompt, default output path).

**Do not modify anything under `/app/model/`.**

## Edge cases the grader probes (via hidden models and prompts)

- Models with **different** `V`, `dim`, `ctx`, and `max_new` than the shipped
  one; your generator must be driven entirely by the model file.
- **Ties**: two candidates with equal maximal score — the lower id must win.
- **Prompts shorter than `ctx`** — use whatever context is available.
- **`max_new = 0`** — `continuation` is `[]` and `full` equals the prompt.
- **Repeated tokens / cycles** — allowed and expected; no repetition penalty.
- The distractor sampling fields are nonzero in every model — applying any of
  them changes the sequence and fails the check.

The grader re-runs your `/app/generate.py` unchanged on the shipped model and
on hidden models/prompts and compares the JSON token-for-token.
