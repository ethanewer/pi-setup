# Q5 mutagenesis primer design for a circular plasmid

You are a DNA-protocol engineer. A **circular** plasmid (DNA ring) holds a known
nucleotide sequence. You must splice a nucleotide **payload** into the plasmid
and design the Q5 mutagenesis primer pair (forward + reverse) that would
reproduce that edit in the lab. Concretely: compute the mutated circular
plasmid DNA, derive the two primers under deterministic orientation/junction
rules, validate both primers against standard constraints, and emit everything
in exact FASTA / text formats.

## Inputs

- `/app/plasmid.fa` — a FASTA file with one record. Its name line is
  `>circular_plasmid`; the following line is the plasmid as a single uppercase
  string over the nucleotides `A/C/G/T`. **The plasmid is circular**: the ring
  has no true ends. We still index the written string `0..L-1`, and any index
  arithmetic is taken **modulo `L`** (index `L` wraps to `0`, `-1` wraps to
  `L-1`, etc.).
- `/app/edit.txt` — one line with two space-separated tokens: a 0-based
  **insertion position** `p`, then the nucleotide **payload** `P` to insert.
  The mutated plasmid is formed by inserting `P` immediately **before** the
  nucleotide currently at index `p` of `S`.

## Step 1 — Mutated circular plasmid

Let `S` be the plasmid sequence (length `L`) and `P` the payload. The mutated
plasmid string is:

```
M = S[0:p] + P + S[p:L]
```

(read the ring starting at the same first character as the input file).

## Step 2 — Q5 mutagenesis primer pair

Derive two primers, each exactly 20 nucleotides long, both uppercase DNA:

1. **Forward primer `F`.** Take the 10 nucleotides of `S` that immediately
   precede position `p`, in circular order (walk backward from index `p-1`,
   wrapping to `L-1` when below 0, until you have collected 10 nucleotides).
   Then concatenate those 10 nucleotides with the first 10 nucleotides of the
   payload. The result is `F` (20 nucleotides).
2. **Reverse primer `R`.** Take the 20-nucleotide window of `M` given by
   `M[p-8 : p+12]` (8 nucleotides just before the insertion in `M`, followed by
   the first 10 nucleotides starting at the insertion point). `R` is the
   **reverse complement** of that window: reverse the window, then map
   `A↔T` and `G↔C`.

## Step 3 — validate constraints

Check both primers against the standard lab constraints:

- length in `[18, 25]` nucleotides, and
- GC content (fraction of `G`+`C` among all nucleotides) in `[0.40, 0.60]`.

For this particular input both primers satisfy both constraints. After both
checks pass, write a single line `OK` to `/app/validation.txt`; if any check
fails, write `FAIL` instead.

## Deliverables (exact)

Write three files:

1. `/app/plasmid_mutated.fa`:
   ```
   >circular_plasmid
   M
   ```
   (`M` on one line.)
2. `/app/primers.fa` — exactly two FASTA records, in this order:
   ```
   >forward
   F
   >reverse
   R
   ```
   (`F` and `R` each on their own line.)
3. `/app/validation.txt` — a single line `OK` (or `FAIL`).

You may use Biopython (installed) to parse FASTA, reverse-complement, and
measure GC fraction. The verifier independently reconstructs the intended `M`,
`F`, `R` from the two input files with the same rules and compares
byte-for-byte after normalizing line endings.

Hints: for the given data the mutated plasmid is 26 nucleotides long, and the
10 nucleotide "upstream" window for `F` wraps across the plasmid boundary.
Spot-check your reverse complement on 4-5 characters by hand before trusting
any library output.