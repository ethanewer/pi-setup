# Assemble overlapping laboratory reads

A wet-lab partner exported a set of DNA reads from a sequencer into
`/app/reads.txt` in FASTA format. You must write a small reusable Python
program that assembles any such read set into a single contiguous sequence
(the "contig"), and then run it on `/app/reads.txt`.

## Input format (`/app/reads.txt`)

Standard FASTA. Supported tolerances:

- A record starts with a header line beginning with `>` (the identifier and
  any free text after it are ignored); every following non-header line is
  sequence that must be concatenated onto the current record.
- Blank lines are ignored.
- There may be several sequence lines per record (they are concatenated).
- A read's sequence characters are restricted to the letters `A`, `C`, `G`,
  `T`. The file may contain 0, 1, or many reads.

## Deliverables (all must be produced under `/app`)

1. `/app/solve.py` — a **reusable script** implementing the assembly contract
   below. It must work on **any** FASTA file following the input rules, not
   just today's example.

   Contract: `python3 /app/solve.py <input.fa> <output.txt>` reads the FASTA
   file `<input.fa>`, computes the assembled superstring, and writes it to
   `<output.txt>` **as a single line followed by a newline**. Exit status 0 on
   success.

2. `/app/contig.txt` — the result of running your assembled script on the
   given file:
   `python3 /app/solve.py /app/reads.txt /app/contig.txt`.

Do **not** modify `/app/reads.txt` or anything under `/tests`.

## Assembly contract (the exact algorithm to implement)

Build the shortest string that contains **every** read as a contiguous
substring, by greedy maximum-overlap merging:

1. **Parse** all reads (concatenate multi-line records; ignore header text
   and blank lines).
2. **De-duplicate**: identical reads collapse to one.
3. **Absorb substrings**: any read that is a contiguous substring of another
   remaining read (even of different length) is removed — it needs no
   characters of its own.
4. **Merge loop**: while more than one sequence remains, consider every
   ordered pair `(a, b)` of **distinct** remaining sequences and compute the
   maximum overlap `L` = the length of the longest suffix of `a` that equals
   a prefix of `b` (`L = 0` when there is none). The merged string is
   `a + b[L:]`. Pick the pair with the **largest** overlap; break ties first
   by the **lexicographically smallest merged string**, then by the smallest
   pair of indices `(i, j)` in the current list. Replace the two chosen
   sequences with their merge.
5. Write the final single string as one line plus a trailing newline.

## Edge cases the verifier will probe (equivalent to your visible case)

- **Single read**: the contig is exactly that read.
- **Empty input** (`0` reads): the output file contains an empty line.
- **Contained / duplicate reads**: shorter reads that appear inside a longer
  one contribute nothing (see step 3); exact duplicates collapse.
- **No overlap at all**: reads are still merged — the same greedy rule
  (largest overlap `0` for every pair, then lexicographically smallest
  merged string) decides the concatenation order.
- **Multi-line records** and **header description text** are tolerated.

Guarantee your output always contains every original read as a substring of
the final contig.

## Success criteria

`/app/solve.py` assembles the reads in `/app/reads.txt` into `/app/contig.txt`
correctly, and the script also runs correctly on the hidden cases described
above (fresh reads, fresh numbers, including the edge cases). The verifier
executes your script — it does not just read a fixed answer.