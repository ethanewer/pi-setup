# saffron-rune — a deterministic hashed-token SMILES featurizer

The **Saffron Runes** cheminformatics group trains a small property-prediction
model on a molecule catalog. Training needs the catalog's `smiles` column
turned into fixed-size float32 vectors, and the evaluation harness must be
able to vectorize the *hidden* test set **identically** — so the featurizer
must be a reproducible, self-contained function with an exact, published
algorithm. Ambiguity is the enemy: the same SMILES must map to the same
bytes, always.

You author the featurizer and the feature file. **No RDKit, no cheminformatics
toolkit** — the transformation below is purely lexical and runs on the Python
3.12 standard library plus `numpy`.

## Deliverables

1. `/app/featurize.py` — an importable module exposing exactly:
   - `VEC_DIM = 96`
   - `featurize_one(smiles: str) -> np.ndarray` — one vector, shape `(96,)`,
     dtype `float32`;
   - `featurize_column(smiles_list) -> list[np.ndarray]` — applies
     `featurize_one` element-wise, **preserving order**.
2. `/app/features.npz` — produced by **running your own featurizer** over the
   `smiles` column of `/app/molecules.csv` in file row order, and saved with
   `numpy.savez` (or `savez_compressed`):
   - key `"X"` — `np.stack` of the per-row vectors, shape `(10, 96)`,
     dtype `float32`;
   - key `"ids"` — the 10 `id` values, in file order (a numpy array of strings
     is fine).

## Fixture (read-only — do not modify)

`/app/molecules.csv` has the header `id,smiles` and 10 data rows. Some rows
are deliberately invalid or empty; they get all-zero vectors (see below).

## The exact featurization algorithm

Implement `featurize_one` **exactly** as follows (the harness recomputes this
independently and compares bytes):

**Constants**

- `VEC_DIM = 96`
- The allowed character set is exactly this string (order irrelevant, it is a
  set):
  ```
  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789()[]+=#%@/.$-
  ```
  Nothing else is allowed — in particular **no space, underscore, backslash,
  colon, asterisk, or any non-ASCII character**.

**Steps** (with `s` the input string):

1. Strip both ends: `s = smiles.strip()`. If `s` is empty, return the
   all-zero `(96,)` float32 vector.
2. If **any** character of `s` is not in the allowed character set, return
   the all-zero vector. (Never raise on bad input.)
3. Tokenize `s` left to right with a scan index `i`, building a list of
   string tokens:
   - If `s[i] == '['`: find the next `']'` at position `j > i`. If there is
     none, the string is invalid — return the all-zero vector. Otherwise the
     token is the whole bracketed span `s[i..j]` **inclusive** (e.g.
     `[Na+]`, `[C@@H]`), and `i` jumps to `j + 1`.
   - Else if the two characters `s[i:i+2]` are exactly `Cl` or `Br`: the
     token is those two characters and `i += 2`.
   - Else: the token is the single character `s[i]` and `i += 1`.
4. For each token at **token position** `i = 0, 1, 2, ...` (position within
   the token list, not the character offset):
   - `tid = 0`; then for each character `ch` of the token, in order:
     `tid = (tid * 131 + ord(ch)) % 1000003`.
   - `bin = (i * 31 + tid) % 96`.
   - `X[bin] += 1.0`.
5. Return `X` as `dtype float32`, shape `(96,)`.

`featurize_column` returns `[featurize_one(s) for s in smiles_list]` — same
length as the input list, order preserved. An empty input list yields `[]`.

## Rules

- Determinism is absolute: calling the function twice on the same string must
  return byte-identical arrays (`a.tobytes() == b.tobytes()`).
- Never raise on any input string — malformed, unclosed bracket, foreign
  characters, empty: all handled per the algorithm.
- Do not modify `/app/molecules.csv`; never read anything under `/tests` or
  `/solution`.
- No network access. Standard library + `numpy` only.

## What the grader does

1. Imports `/app/featurize.py`, checks `VEC_DIM == 96` and that both functions
   are callable, and re-derives every expected vector with its own independent
   implementation of the algorithm above.
2. Runs `featurize_column` on **hidden SMILES lists** (bracket atoms,
   two-letter tokens, unclosed brackets, whitespace-only, non-ASCII and other
   invalid inputs) and requires byte-exact agreement, `(96,)` float32 shapes,
   order preservation, and reproducibility across repeated calls.
3. Re-features the visible catalog and requires `/app/features.npz`'s `"X"` to
   match exactly (shape `(10, 96)`, dtype `float32`, row order = CSV order)
   and `"ids"` to match the CSV `id` column in order.
