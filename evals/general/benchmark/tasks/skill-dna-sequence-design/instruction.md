# DNA sequence design: find a strand satisfying hard constraints

Designing a DNA sequence for a primer/oligo means producing a string over the
nucleotides `A`, `C`, `G`, `T` that satisfies a fixed set of biophysical and
synthesis constraints. There are many valid answers; any string meeting **all**
constraints is correct.

## Constraints

Design a 10-nucleotide DNA strand such that:

1. **Length** is exactly 10.
2. Only the letters `A`, `C`, `G`, `T` are used.
3. Each of the four nucleotides appears **at least once**.
4. No two adjacent characters are identical (no repeated base run).
5. The first character is `A`.
6. The last character is `G`.
7. The strand contains **exactly two** `T` characters.

## Task

Find such a strand and write it as a single line (uppercase, no spaces) to
`/app/designed.txt`.

Example shape (NOT valid — verify against all constraints): `ACGACGACGT`.
One valid candidate is `ACGTACGTAG` — check every constraint yourself before
submitting.

You may write a small Python 3 script to search for a valid strand
(e.g. brute-force or backtracking over the small search space), or reason it
out by hand. The verifier independently checks all seven constraints against
whatever you wrote to `/app/designed.txt`.