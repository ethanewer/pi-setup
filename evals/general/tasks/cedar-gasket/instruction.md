# cedar-gasket — a compact neural feature stack

**Gavel Labs** is standing up a small embedding-based research pipeline. You
must build three things under `/app`:

1. a PyTorch **attention-gated pooling module**,
2. **word embeddings** that solve vector analogies and reflect semantic
   similarity,
3. a reproducible **SMILES → feature-array featurizer** plus its feature output.

The read-only fixtures `/app/relations.json` and `/app/molecules.csv` are
already on disk. **You must not modify or delete any file under `/app` that you
did not create yourself, and you must never read or touch anything under
`/tests` or `/solution`.** Every deliverable will be re-checked on **hidden**
data (fresh batch tensors, hidden analogy quadruples, and a fresh SMILES list),
so nothing may be hard-coded to today's visible data.

---

## 1. `/app/pooling.py` — attention-gated pooling in PyTorch

Define a class `AttentionGatedPooling(torch.nn.Module)` with **these exact
attribute names** (they are checked by the harness):

- `self.gate_a` — a `torch.nn.Linear(in_dim, gate_hidden)` that first transforms
  each bag element;
- `self.gate_b` — a `torch.nn.Linear(gate_hidden, 1)` that reduces each element
  to a single scalar **logit**;
- `self.aggregate` — a `torch.nn.Linear(in_dim, out_dim)` that maps the pooled
  vector to the output.

Constructor: `AttentionGatedPooling(self, in_dim, gate_hidden, out_dim)`.

Provide two methods:

- `attention_weights(self, x)` — with `x` of shape `(bag, in_dim)`, compute
  `logits = self.gate_b(torch.tanh(self.gate_a(x)))` of shape `(bag, 1)`, then
  return `torch.softmax(logits, dim=0)` — a `(bag, 1)` tensor of **attention
  weights that sum to 1 over the bag**.
- `forward(self, x)` -> `(pooled, weights)` — returns `weights` (from
  `attention_weights`) and `pooled = self.aggregate((x * weights).sum(dim=0,
  keepdim=True))`, a `(1, out_dim)` tensor.

The module must work for **any bag size >= 1** (softmax over a single element is
1.0) and any rank-2 input. All tensors are default-dtype float32 on CPU.

## 2. `/app/embeddings.npy` — word vectors that solve word analogies

`/app/relations.json` describes a small vocabulary of 24 **invented** words:

- `words` — a length-24 list; row `i` of your embedding matrix must be the vector
  for `words[i]`.
- `categories` — 12 entries, each `{"name": "...", "adult": "...", "young":
  "..."} ` (e.g. `brim` -> adult `brimsan`, young `brimleg`).
- `quadruples` — example analogies `{"a","b","c","d"}` meaning
  "**a is to b, as c is to d**". All share the same adult->young relationship: a
  pair from one category is compared with the adult->young pair of a different
  category.

You must produce `/app/embeddings.npy`: a 2-D **float32** numpy array of shape
`(24, DIM)` where `DIM` is given by the JSON `"dim"` field (= 48). Row `i` is
the embedding of `words[i]`.

Your embeddings must satisfy both properties for the **entire** vocabulary:

1. **Analogies.** For every quadruple, the arithmetic
   `v(a) - v(b) + v(c)` must, by **cosine similarity** against all other
   vocabulary words, rank `v(d)` **first**. The harness will also test hidden
   quadruples that are **different cross-category combinations over the same
   vocabulary**, so a genuine construction that generalizes is required;
   over-fitting the given examples will fail the hidden batch.
2. **Similarity.** Every semantically related pair — the `adult` and `young`
   member of the **same category** — must have **positive** cosine similarity.

A natural construction that satisfies both: give every category an orthogonal
"category" direction and share one fixed adult->young direction across all
categories. Then `v(adult(c)) - v(young(c))` is the **same vector** for every
category `c`, so `v(a)-v(b)+v(c) == v(d)` for any two distinct categories — and
same-category words (which share one category direction) are highly correlated
cosine-wise. You may build the directions with `numpy` (e.g. an orthonormal basis
from `np.linalg.qr` for the per-category directions). The ratio/magnitudes are free; only the relationship properties are
judged. **Row alignment and `float32` are mandatory**; the verifier loads
`words` from
`/app/relations.json` and compares your matrix row-for-row against its own
expectations.

---

## 3. `/app/featurizer.py` + `/app/smiles.npz` — SMILES featurization

`/app/molecules.csv` has a header `id,smiles` and 8 molecule rows.

Write `/app/featurizer.py` that exposes:

- `VEC_DIM = 128`
- `RADIUS = 2`
- `featurize_one(smiles: str) -> np.ndarray` — a deterministic `float32` array
  of shape `(VEC_DIM,)`:
  1. `m = rdkit.Chem.MolFromSmiles(smiles.strip())`;
  2. if `m is None` (invalid, malformed, or empty/whitespace-only SMILES),
     return `np.zeros(VEC_DIM, dtype=np.float32)`;
  3. otherwise compute a fixed-size MORGAN bit fingerprint,
     `AllChem.GetMorganFingerprintAsBitVect(m, radius=RADIUS, nBits=VEC_DIM)`,
     and return `np.array(list(bv), dtype=np.float32)`.
- `featurize_smiles(smiles_list: list[str]) -> list[np.ndarray]` — applies
  `featurize_one` to each element, preserving order.

The featurizer must be **purely deterministic** (same input -> byte-identical
output) so the harness can vectorize hidden SMILES identically to you.

Then produce `/app/smiles.npz` by **running your own featurizer** over the
`smiles` column of `molecules.csv`, in file order, and saving:
- key `"X"` -> `np.stack` of the 8 vectors, shape `(8, VEC_DIM)`, dtype `float32`;
- key `"ids"` -> the 8 ids, in file order.

Save with `np.savez_compressed` or `np.savez`.

---

## Explicit requirements & edge cases

- **Path overrides matter.** Array shapes/dtypes must match exactly; row order
  must match `words` / the CSV row order.
- **Blank or invalid SMILES -> all-zero vector.** Never raise on bad input.
- **Pooling must handle a single-element bag.**
- Do not modify `/app/relations.json`, `/app/molecules.csv`.
- Never read `/tests` or `/solution`.

## Success criteria (what the verifier runs)

1. Imports `AttentionGatedPooling` from `/app/pooling.py`, confirms it is a real
   `nn.Module` with the three fixed attribute names, and runs its forward on
   hidden bag tensors, checking the `(bag,1)` weight shape and that the weights
   sum to 1 over the bag.
2. Loads `/app/embeddings.npy` aligned to `words`, ranks `v(a)-v(b)+v(c)` over
   the vocabulary for hidden analogy quadruples and requires the target to place
   first, and requires positive cosine similarity on every same-category pair.
3. Runs `/app/featurizer.py::featurize_smiles` on a hidden SMILES list (including
   invalid / empty / whitespace-only entries) and checks `(VEC_DIM,) float32`
   shape, reproducibility, and **byte-exact equality to the independent RDKit
   reference**; checks `/app/smiles.npz` shape/dtype and that its `X` matches your
   featurizer on the visible catalog.