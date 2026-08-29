# amber-helix — the Kayak/QD batch job

## Objective

The **Kayak/QD** cheminformatics batch at **Novaprime** glues three small
computational jobs together. Your task is to author three Python programs in
`/app`, run them so they emit three JSON artifacts into `/app`, and make sure
every program generalises to fresh inputs (the verifier will re-execute each
program against brand-new catalogs, loci/templates and descriptor/measurement
matrices). The three jobs are independent of each other.

Deliverables (all must exist after you are done):

| path | what it is |
|---|---|
| `/app/load_catalog.py` | catalog loader/filterer (importable module + CLI) |
| `/app/filtered_catalog.json` | output of running it on the default catalog |
| `/app/design_primers.py` | mutagenesis primer designer (module + CLI) |
| `/app/primers.json` | output of running it on the default mutation scene |
| `/app/train_affinity.py` | binding-affinity model tuner (module + CLI) |
| `/app/affinity_report.json` | output of running it on the default affinity data |

The three programs must be **executable** (`chmod +x`) and runnable from the
shell with `python3 /app/<name>.py ...`. The artifacts above are produced by
**running** the programs, not by hand.

---

## 1) Molecular catalog filter — `/app/load_catalog.py`

`/app/catalog.json` is a JSON **array** of molecule records. Each record has at
least:

```json
{ "id": "NVX-0001", "name": "Galogine", "smiles": "...",
  "mol_weight": 196.2, "logP": 1.12 }
```

Names may be padded with surrounding spaces and may appear with **any** casing.

### Module contract

Implement a function

```python
def filter_catalog(catalog_path: str, names: list[str],
                   limit: int | None = 1000) -> list[dict]:
```

that **re-reads `catalog_path` from disk on every call** (no caching) and
returns the records — in catalog order — whose **trimmed** `name` equals, case-
insensitively (compare `name.strip().lower()`), the trimmed form of **any**
entry in `names`. Rules:

- A record whose `name` is missing, not a string, or blank is **skipped**
  (never an error).
- Records may repeat in the catalog; a duplicate that matches is returned once
  per occurrence.
- The result is truncated to `limit` matches (stop as soon as `limit` matches
  are collected). `limit=None` or `0` means unlimited.
- Output preserves catalog order.

### CLI

```
python3 /app/load_catalog.py --catalog <path> --names <names-file> \
    [--limit N] --out <out.json>
```

- `--names` is a plain-text file, one name per line (lines are stripped).
- Writes the matching records as a JSON array to `--out`.
- **Default run** (this is what produces the deliverable):
  `python3 /app/load_catalog.py --catalog /app/catalog.json --names
  /app/wanted_names.txt --limit 1000 --out /app/filtered_catalog.json`
- If the catalog file is missing, unreadable, or malformed (e.g. invalid JSON),
  print an error to stderr and **exit non-zero**. A non-matching name in the
  list is simply ignored.

### Edge cases the verifier probes (handle them exactly as above)

- an **empty** names file → exit 0 and write an **empty array**;
- names padded with leading/trailing spaces that match a padded/normal name →
  match (trim before comparing);
- `--limit 1` → only the **first** match in catalog order;
- a catalog containing an entry with **no `name` field** → that entry skipped;
- a **malformed** catalog file (trailing comma) → **non-zero exit**;

---

## 2) Mutagenesis primer design — `/app/design_primers.py`

`/app/target.fasta` is a FASTA with exactly one record: the **sense** strand of
a gene, written 5′→3′ using only `A`, `C`, `G`, `T`. `/app/mutation_scene.json`
describes the mutation:

```json
{
  "template": "/app/target.fasta",
  "template_id": "novelix-Barcase-2",
  "gene": "adkZ",
  "locus":       { "start": 150, "end": 152 },
  "mutant": "TAA",
  "anneal_length": { "min": 18, "max": 24 },
  "tm":            { "min": 55.0, "max": 64.0 },
  "tm_target": 60.0
}
```

`locus` is **1-based inclusive** on the sense strand (base 150 was `start`-th
base of the strand). The reaction replaces the sense bases at `[start, end]`
with `mutant` (mutant length must equal `end - start + 1`).

### Design rules

**Forward primer (5′→3′)** = the sense-strand segment immediately **upstream** of
the locus, of length `anneal_length` (call it `lf`), **followed by** `mutant`.
So if `seq` is the sense strand, with 0-based positions:

```
forward_seq      = seq[ (start-1-lf) : (start-1) ] + mutant
forward_anneal   = seq[ (start-1-lf) : (start-1) ]        # annealing region
```

**Reverse primer (5′→3′)** = the **reverse complement** of the sense-strand
segment immediately **downstream** of the locus, of length `anneal_length`
(`lr`), followed by the reverse complement of `mutant`:

```
rc(seq[end : end+lr]) + rc(mutant),   where end is the 0-based base just after locus
```

`rc(s)` = reverse-then-Watson-Crick-complement (`A<->T`, `C<->G`).

**Melting temperature** of an annealing region is the Wallace rule:

```
Tm = 2*(A+T)  +  4*(C+G)     (degrees C, counts over the annealing region)
```

**Length choice:** for forward, try every `lf` in `[anneal_length.min,
anneal_length.max]`; keep only those whose upstream region exists and whose
`Tm(anneal)` lies inside `[tm.min, tm.max]`; pick the `lf` whose Tm is **closest
to `tm.tm_target`** (ties: pick the smaller). Report forward iff such an `lf`
exists. Do the same for `lr` for the reverse primer. The two lengths are
chosen independently.

### Output JSON (`/app/primers.json`)

On success:

```json
{
  "template_id": "...", "gene": "...",
  "locus": {"start": 150, "end": 152}, "mutant": "TAA",
  "anneal_length_bounds": {"min": 18, "max": 24},
  "tm_bounds": {"min": 55.0, "max": 64.0},
  "error": null,
  "forward":  { "seq": "5'->3' primer bases", "orientation": "sense-matched",
                "anneal_length": 20, "anneal_region": "...", "tm": 60.12 },
  "reverse":  { "seq": "5'->3' primer bases", "orientation": "antisense-matched",
                "anneal_length": 21, "anneal_region": "...", "tm": 59.88 }
}
```

If a design is **impossible**, write the JSON **anyway** with `"forward": null`,
`"reverse": null`, and a short `"error"` string. Exactly one of these error
tokens is used, and only they:

- `"template-unreadable"` — FASTA missing/unreadable/empty
- `"non-standard-nucleotide"` — template contains a base outside `ACGT`
  (e.g. `N` or `R`)
- `"locus-out-of-range"` — locus outside the template
- `"length-mismatch"` — `len(mutant) != end-start+1`
- `"mutant-nonstandard"` — mutant has a non-`ACGT` base
- `"insufficient-upstream"` — the locus is too close to the 5′ end
  (`start-1 < min`)
- `"insufficient-downstream"` — the locus is too close to the 3′ end
  (`len(seq)-end < min`)
- `"no-viable-tm-forward"` / `"no-viable-tm-reverse"` — no length in range has a
  Tm inside the bounds

### CLI

```
python3 /app/design_primers.py --scene <scene.json> --out <out.json>
```

**Default run** (produces the deliverable):
`python3 /app/design_primers.py --scene /app/mutation_scene.json --out
/app/primers.json`

The program must work for any scene JSON / template supplied as `--scene` (the
verifier feeds fresh loci and templates). Computed `tm` values are rounded to 2
decimals. The anneal regions must cover the **exact** locus-adjacent positions
described above; the 3′ end of each primer encodes the mutation. If `--scene`
itself is missing/unreadable, print to stderr and exit non-zero.

### Edge cases the verifier probes (handle them exactly as above)

- a scene whose locus is too close to the 5′ end → `"insufficient-upstream"`
  error JSON;
- a template FASTA containing `N`/`R` bases → `"non-standard-nucleotide"` error
  JSON;
- a mutant whose length does not match the locus → `"length-mismatch"` error
  JSON;
- a normal valid hidden scene → valid pair passing all bounds.

---

## 3) Binding-affinity model tuning — `/app/train_affinity.py`

`/app/affinity_descriptors.npy` is an `(n, 12)` float matrix of molecular
descriptors; `/app/affinity_measurements.npy` is the matching `(n,)` vector of
measured binding-affinity values (higher = tighter). Achieve a **strict
rank-accuracy** gate on **held-out** data that generalises to a fresh dataset of
the same form (the verifier runs your program on a new descriptor/measurement
pair generated the same way).

### CLI

```
python3 /app/train_affinity.py --descriptors X.npy --targets y.npy \
    [--n_seeds 8] [--out report.json]
```

The program must implement a real feature/model pipeline (you may take
inspiration from scikit-learn but must actually tune/select it):
train/test/model selection is your choice, but you must prove it on a proper
**random holdout** — for each of `n_seeds` random seeds you split the rows into
train (~80%) and test (~20%), fitting on train and scoring **Spearman rank
correlation** between predictions and ground truth on the held-out test rows.

### Report JSON (`/app/affinity_report.json`)

```json
{
  "descriptor_columns": 12, "n_rows": 2000,
  "n_seeds": 8, "threshold": 0.9, "test_fraction": 0.2,
  "all_pass": true, "min_spearman": 0.96,
  "seeds": [
    { "seed": 0, "n_train": 1600, "test_size": 400,
      "spearman": 0.965432,
      "test_ids": [3, 17, ...], "test_pred": [0.1, -2.3, ...] },
    ...
  ]
}
```

Constraints:

- `n_seeds` must equal the requested count and each seed `0..n_seeds-1` must be
  present exactly once; the holdout for each seed must be **different** across
  seeds.
- `test_ids` are integer row indices into the input matrix; `test_pred` the
  predicted values on exactly those rows; the test fraction must stay in
  `[0.1, 0.3]` so the holdout is real (the verifier re-computes Spearman from
  your `test_pred` vs the true values at `test_ids`).
- **Every** seed’s held-out Spearman must be `>= threshold` (0.9), and the
  program must reach that bar on a fresh hidden dataset too. A weak/naive model
  that just linearly regresses the raw features lands around ~0.75 here —
  below the gate — because the true relationship is nonlinear in the
  descriptors; you must discover and exploit that (e.g. a proper nonlinear
  ensemble / feature engineering with cross-validation) to pass robustly across
  all seeds. Tune until `all_pass: true` on the delivered report.
- If the descriptor matrix does not match the target vector **shape**, or either
  file is missing/unreadable, print to stderr and **exit non-zero**. Very small
  datasets (a handful of rows) must still run and emit a report without
  crashing.

**Default run** (produces the deliverable):
`python3 /app/train_affinity.py --descriptors /app/affinity_descriptors.npy
--targets /app/affinity_measurements.npy --n_seeds 8 --out
/app/affinity_report.json`

---

## Constraints

- Write the three programs yourself, fresh, in `/app`; you may use the installed
  packages (numpy, scipy, pandas, scikit-learn, Biopython).
- **Do not** modify `/app/catalog.json`, `/app/wanted_names.txt`,
  `/app/target.fasta`, `/app/mutation_scene.json`, or the `.npy` affinity data —
  they are read-only inputs.
- The three programs must run from a pristine container (`python3 /app/... .py`)
  and must not depend on anything outside `/app` except `/tmp` for scratch.
- The verifier will reject any program that hard-codes a catalog, a template, or
  the affinity dataset instead of reading the path/arguments it is given.
