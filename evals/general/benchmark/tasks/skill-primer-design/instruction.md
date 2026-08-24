# PCR primer design

`/app/sequence.txt` contains on a single line a DNA sequence (uppercase letters, only `A`, `C`, `G`, `T`).

Design a PCR primer pair — a **forward primer** `F` and a **reverse primer** `R` — that satisfy every condition below. This is standard PCR primer design:

1. Each primer is **18–25 nucleotides** long.
2. Each primer has **GC content 40–60%** (fraction of `G`+`C` among A/C/G/T within 40–60 inclusive).
3. `F` must appear **exactly and contiguously** as a substring of the given sequence when both are read in the normal 5′→3′ direction.
4. `R` targets the opposite strand. Therefore the **reverse complement of `R`** (compute as: reverse `R`, then map `A↔T`, `G↔C`) must appear — exactly and contiguously — as a substring of the given sequence.
5. The position where `F` matches and the position where `rc(R)` matches must **not overlap** (the primers must not target the same region of the sequence).

Write two lines to `/app/primers.txt`:

```
F: <forward primer text>
R: <reverse primer text>
```

where the text after `F: ` is your chosen 5′→3′ nucleotide string and the text after `R: ` is your chosen reverse primer nucleotide string. The verifier parses these, applies the reverse-complement test, and checks every condition above (using the same `/app/sequence.txt`). Any valid primer pair satisfying all conditions is accepted — you do not need to match a specific answer.

Python's standard library is sufficient (no external bioinformatics package is needed).