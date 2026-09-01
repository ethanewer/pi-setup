# Circular plasmid splice primer design

You are designing primers for a **single-fragment splice** in a circular plasmid.
The plasmid is a closed DNA ring; your job is to remove a small "seam" region,
splice in a foreign DNA segment at that junction, and produce a correct forward
/ reverse primer pair that flank the seam on the assembled ring. You must then
validate the primers against primer-design constraints.

## Inputs (read-only — do not modify them)

- `/app/plasmid.fasta` — a FASTA file containing exactly one DNA sequence, `V`
  (the plasmid). It may span one or more lines after the `>` name line. The
  plasmid is **circular**: it is stored as a linear string of length `L`, but
  index `i` and index `(i+1) mod L` are adjacent bonds, and the bond between the
  very last character and the very first character is a real bond (the file
  represents a closed ring). Assume only characters `A`, `C`, `G`, `T`.
- `/app/plan.json` — JSON with the splice plan. It gives the exact numbers used
  below.

## Plan fields (read them from `/app/plan.json`)

```json
{
  "back_start": 12,
  "seam_length": 6,
  "insert": "AATGGCGCGTCGTGAATAAC",
  "primer_length": 24,
  "length_range": [20, 35],
  "gc_range": [30, 70],
  "tm_rule": "2/4",
  "tm_range": [20, 75]
}
```

- `back_start` = index (0-based) where the seam begins on the ring.
- `seam_length` = number of DNA chars in the seam removed from the ring.
- `insert` = the DNA segment spliced in where the seam was.
- `primer_length` = desired length (chars) of each designed primer.

All indices are 0-based. `back_start + seam_length <= L`.

## The assembled (spliced) ring

Removing `V[back_start : back_start+seam_length]` and splicing `insert` in its
place yields a new linear string that represents the closed ring starting again
at index 0:

```
assembled = V[0 : back_start] + insert + V[back_start+seam_length : L]
```

## Primer definitions (exact; this is a Golden-Gate-style single junction)

To reason about circular windows, form the length-`2L` tape `T = V + V`. A
window that starts near the circular boundary is then continuous.

1. **forward primer** = the `primer_length` DNA characters that immediately
   precede the seam moving *counterclockwise* along the ring (i.e. ending just
   before `back_start`). Concretely, from the tape:
   ```
   forward = T[ L + back_start - primer_length  :  L + back_start ]
   ```
   (When `back_start - primer_length < 0`, this window wraps the boundary, as it
   must because the ring is closed.) The forward primer is written 5' to 3' 
   running along the ring toward the seam.
2. **reverse primer** is the reverse complement of the `primer_length` characters
   immediately *after* the seam in the counterclockwise direction (the first
   chars of the segment glued after the insert). Concretely:
   ```
   window              = T[ back_start + seam_length : back_start + seam_length + primer_length ]
   reverse             = reverse_complement(window)
   ```
   Reverse complement definition: `reverse_complement(s)` reverses `s` and
   maps each base to its Watson–Crick mate: `A<->T`, `C<->G`.

## Validation constraints (all must hold for each primer)

- **length**: `primer_length` must lie in `length_range` .
- **GC%**: fraction of chars that are `G` or `C`, as a percentage, must lie in
  `gc_range` (`[30,70]`).
- **melting temperature** (`tm_rule` = `"2/4"`): count `a` = number of `A`/`T`
  chars and `g` = number of `G`/`C` chars in the primer; then
  `Tm = 2*a + 4*g` (an integer). `Tm` must lie in `tm_range` (`[20,75]`).

## Deliverable

Write a Python 3 program `/app/design_primers.py` that:
1. loads the FASTA sequence `V` (joins all DNA lines, ignores the `>` line),
2. loads `/app/plan.json`,
3. computes `assembled`, `forward`, and `reverse` exactly as above,
4. computes the validation flags above and the boolean `valid`,
5. writes `/app/primers.json`:

```json
{
  "assembled": "<full spliced ring, linear string starting at index 0>",
  "forward": "<forward primer>",
  "reverse": "<reverse primer>",
  "length_ok": true,
  "gc_ok": true,
  "tm_ok": true,
  "valid": true
}
```

Then run it so the JSON is produced. Every boolean must be `true`. (You may use
`biopython` if installed, but the Python standard library is fully sufficient;
do not add third-party dependencies beyond what is already present.)

**Independent self-checks** before finalizing (do these in your own scratch
code, shown in your reasoning, not in the delivered program):
- Confirm `assembled` length equals `L - seam_length + len(insert)`.
- Confirm `assembled` starts with `V[0:back_start]` and then the insert.
- Confirm the forward primer begins where the ring's preceding DNA meets the
  seam, and that the reverse primer is genuinely the reverse complement (never
  the same string as the forward primer in the same orientation).

## Notes / conventions

- DNA is case-sensitive uppercase only. Preserve exact case.
- The ring boundary guarantees wraparound: do not "clip" at end-of-file; use the
  tape construction above.
- The grader recomputes the expected strings from the the given inputs and compares
  `assembled`, `forward`, `reverse` to your JSON exactly, and requires all flags
  true.