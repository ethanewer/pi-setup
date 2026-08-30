# Sable Codon — mutagenic primer designer

The **Sable Codon** enzyme-engineering lab orders QuikChange-style primers for
site-directed mutagenesis. You must write a reusable primer-design program and
run it on the shipped reaction scene.

## Environment

- Working directory: `/app`. The read-only inputs `/app/plasmid.fasta` and
  `/app/scene.json` already exist. Python 3.12 (`python3`), standard library
  only, no network.
- **Do not modify `/app/plasmid.fasta` or `/app/scene.json`.**

## Deliverables (both required)

1. `/app/design.py` — a runnable Python program:
   ```
   python3 /app/design.py --scene <scene.json> --out <out.json>
   ```
   It must work on **any** scene/template conforming to the contract below
   (the verifier re-runs it on fresh hidden scenes).

2. `/app/primers.json` — the design produced by running your program on the
   shipped scene:
   ```
   python3 /app/design.py --scene /app/scene.json --out /app/primers.json
   ```

## Scene format (`scene.json`)

```json
{
  "template": "/app/plasmid.fasta",
  "template_id": "pSable-9",
  "locus": {"start": 180, "end": 182},
  "insert": "GTA",
  "anneal": {"min": 8, "max": 16},
  "tm":     {"min": 60.0, "max": 82.0, "target": 70.0},
  "gc":     {"min": 35.0, "max": 65.0}
}
```

- The FASTA may contain **several records**; the design uses the record whose
  id (first whitespace-delimited token after `>`) equals `template_id`.
- `locus` is **1-based inclusive** on the sense strand: bases
  `[start, end]` are replaced by `insert`. `end == start - 1` is allowed and
  denotes a **pure insertion** between bases `start-1` and `start` (zero
  wild-type bases replaced); `insert` may be shorter, equal, or longer than
  the replaced segment. Nucleotides are uppercase `A`/`C`/`G`/`T` (lowercase
  accepted and treated as uppercased).

## Primer design rules

With `up = sense bases before the locus` (i.e. bases `1..start-1`) and
`down = sense bases after the locus` (bases `end+1..len`):

- **Forward primer (5′→3′)** = the last `L_f` bases of `up` + `insert` + the
  first `R_f` bases of `down`, i.e. the exact sense-strand segment of the
  **mutant** molecule centred on the mutation.
- **Reverse primer (5′→3′)** = the **reverse complement** of the same kind of
  fragment built with lengths `L_r, R_r`:
  `rc( down-segment ) + rc( insert ) + rc( up-segment )`.
- `rc(s)` = reverse, then Watson-Crick complement (`A<->T`, `C<->G`).
- **Melting temperature (Wallace rule)** over the **entire primer**
  (flanks + insert): `Tm = 2*(A+T) + 4*(G+C)` degrees C.
- **GC percent** of the entire primer: `100*(G+C)/len`, compared as an exact
  real number against `[gc.min, gc.max]` (the reported value is rounded to
  1 decimal).
- **Length choice** (for each primer independently): try every
  `(L, R)` with `L` and `R` each in `[anneal.min, anneal.max]` and with the
  flanks actually available. A pair is **viable** when
  `tm.min <= Tm <= tm.max` **and** `gc.min <= GC% <= gc.max`. Among viable
  pairs pick the one minimising, in order:
  1. `|Tm - tm.target|`
  2. total anneal length `L + R`
  3. `L` (smaller upstream length wins ties)

## Output JSON

On success (`"error": null`):

```json
{
  "template_id": "pSable-9",
  "locus": {"start": 180, "end": 182},
  "insert": "GTA",
  "anneal_bounds": {"min": 8, "max": 16},
  "tm_bounds": {"min": 60.0, "max": 82.0, "target": 70.0},
  "gc_bounds": {"min": 35.0, "max": 65.0},
  "error": null,
  "forward": {"seq": "...", "upstream_len": 9, "downstream_len": 13,
               "tm": 70.0, "gc_percent": 40.0},
  "reverse": {"seq": "...", "upstream_len": 9, "downstream_len": 13,
               "tm": 70.0, "gc_percent": 40.0}
}
```

`tm` is reported as a float (Wallace values are integral, e.g. `70.0`);
`gc_percent` rounded to 1 decimal.

When a design is **impossible**, still write the JSON with `"forward": null`,
`"reverse": null` and `"error"` set to **exactly one** of these tokens, checked
in this order:

- `"template-unreadable"` — FASTA missing/unreadable/empty or has no records
- `"template-id-not-found"` — no record id equals `template_id`
- `"non-standard-nucleotide"` — the selected record has a base outside `ACGT`
- `"insert-nonstandard"` — `insert` is not a non-empty string of `ACGT`
- `"locus-out-of-range"` — `start < 1`, or `end < start - 1`, or `end > len`
- `"insufficient-upstream"` — `start - 1 < anneal.min`
- `"insufficient-downstream"` — `len(seq) - end < anneal.min`
- `"no-viable-design-forward"` — no viable `(L,R)` for the forward primer
- `"no-viable-design-reverse"` — no viable `(L,R)` for the reverse primer

If the `--scene` file itself is missing, unreadable, or not valid JSON with
the required fields, print an error to stderr and **exit non-zero** (no output
JSON). A scene that yields a design error token still exits **0**.

## Edge cases the verifier probes

- a valid **substitution**, a valid **insertion** (`end == start - 1`), and a
  valid **deletion** (insert shorter than the replaced segment);
- a scene whose locus sits too close to the 5′ end (`insufficient-upstream`);
- a multi-record FASTA where `template_id` selects between records, and a
  scene naming a record that does not exist;
- Tm bounds no candidate can meet (`no-viable-design-forward`);
- the exact tie-break order above (several pairs may share the minimal
  `|Tm - target|`).

## Constraints

- Standard library only; deterministic; no hard-coding of the shipped
  template or scene values.
- The anneal regions must flank the **exact** locus positions described; a
  reversed or misordered binding site produces a wrong fragment and fails the
  grader.
- Do not read from `/tests`; do not modify the shipped inputs.
