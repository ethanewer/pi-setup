# Item-057 (medium) — FRET pair screening, DHFR protein cross-checks, DNA codon design

You are an assay designer working with a local knowledgebase under
`/app/data/`. It holds FPbase-style donor/acceptor **fluorescence spectra**, a
curated **codon table**, a synthetic **DHFR protein** record, and a
**provenance** map. You must (a) screen fluorescent pairs by spectral overlap,
(b) cross-check the protein's sequence against its recorded metadata, and (c)
design **DNA** that encodes the protein in codon space, then write everything
to one machine-readable result. Track data provenance as you go.

## Inputs (all under `/app/data/`; do not modify)

- `pair_{A,B,C}_donor_emission.csv` — donor fluorescence *emission* spectrum;
  columns `wavelength_nm,intensity`. Wavelengths run 400…700 in 5 nm steps.
- `pair_{A,B,C}_acceptor_absorption.csv` — acceptor *absorption* spectrum;
  columns `wavelength_nm,intensity` (same grid).
- `fluorophores.json` — per-pair donor/acceptor names, peaks, donor quantum
  yield.
- `dhfr_protein.json` — the engineered DHFR protein: `sequence` (amino-acid
  string), `record_residue_count`, `record_g_fraction`, `record_charged_count`,
  and provenance (`source_id`, `fetched_from`, `fetched_on`).
- `codon_table_full.json` — `table` maps amino-acid letter → list of valid
  synonymous codon strings; `stop_codons` lists valid stop codons.
- `sources.json` — provenance map: each data file → `{source_id, fetched_from,
  fetched_on}`.

## Your analysis (exact formulas)

### 1. FRET overlap (fluorescent pairs)

For each pair `P` in `{A,B,C}`:
- Load donor emission `Em` and acceptor absorption `Ab` (same wavelength grid).
- Normalize each to its peak: `em = Em / max(Em)`, `abn = Ab / max(Ab)`.
- Compute the spectral-overlap integral `J_P`:
  ```
  J_P = sum_i ( em[i] * abn[i] ) * 5   # 5 = delta-lambda in nm
  ```
- Report `overlap = {"A": J_A, "B": J_B, "C": J_C}` (floats, arbitrary
  precision) and `best_pair` = the key with the largest `J`.

You may use `fluorophores.json` to sanity-check: the best pair should have a
donor emission band that overlaps the acceptor absorption band (its `J`
dominates). This is a thin spectral-overlap screen for a FRET / assay.

### 2. Cross-check the protein record

The `dhfr_protein.json` `sequence` is authoritative. Compute:
- `residue_count` = the **actual** number of amino-acid characters in
  `sequence`. Do **not** blindly trust `record_residue_count` — cross-check it
  and report the real value from the string.
- `g_fraction` = `sequence.count('G') / residue_count`.
- `g_fraction_match` = `True` iff `abs(g_fraction - record_g_fraction) <=
  0.005`, else `False`.

### 3. DNA codon design

Using `codon_table_full.json` as the authoritative synonym table, design one
DNA codon (`3` chars) for **every residue of `sequence` that has an entry in
the codon table** (amino acids without a codon entry are simply skipped). Join
those codons in protein order into a single DNA string `dna`. Then compute:
- `mapped_count` = number of encoded residues.
- `gc_fraction` = `(dna.count('G') + dna.count('C')) / len(dna)`.
- `dna_length` = `len(dna)` (must equal `3 * mapped_count`).

The DNA is valid iff you can **decode** it back: split `dna` into 3-char
chunks; each chunk must be one of the codon options for the amino acid at that
position.

### 4. Provenance

`provenance_ok` = `True` iff every **spectra CSV** you used
(`pair_A/B/C_*_donor_emission.csv` + `pair_A/B/C_*_acceptor_absorption.csv`),
plus `fluorophores.json` and `dhfr_protein.json`, has an entry in
`sources.json` (regardless of value). The codon tables are local reference
lookups and are exempt.

## Output

Write **`/app/result.json`** with exactly these keys:

```json
{
  "overlap":       { "A": 34.1, "B": 3.5, "C": 18.3 },
  "best_pair":     "A",
  "residue_count": 159,
  "g_fraction":    0.0629,
  "g_fraction_match": true,
  "hascodable_dna": "...",      // your DNA string
  "mapped_count":  126,
  "dna_length":    378,
  "gc_fraction":   0.72,
  "provenance_ok": true
}
```

(`hascodable_dna` is the DNA you designed in step 3.) The grader recomputes all
of these from the fixed files under `/app/data/` and compares.

## Success criteria (grader)

- `overlap` values: within `1e-3` of the grader's recomputation per pair.
- `best_pair` matches the grader's argmax.
- `residue_count` and `g_fraction` match the grader's (computed from the raw
  sequence) within `1e-6` (residue_count) / `1e-4` (g_fraction).
- `g_fraction_match` matches the grader's boolean.
- DNA: `dna_length == 3 * mapped_count` and the DNA **decodes** to exactly the
  amino acids that have codon entries (same order); `gc_fraction` in
  `[0.15, 0.85]`.
- `provenance_ok` is `true`.

You never see the grader's expected values; implement the definitions literally
and your numbers will match.