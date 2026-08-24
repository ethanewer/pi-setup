In `/app` there is a file `dna.txt` containing a DNA nucleotide sequence on a single line, using only the uppercase letters `A`, `C`, `G`, `T`.

Write a Python script `/app/dna.py` that:

1. Reads the nucleotide sequence.
2. Computes its Watson–Crick complement: map each nucleotide by `A`↔`T` and `C`↔`G` (in the same order, i.e. `A->T`, `T->A`, `C->G`, `G->C`).
3. Computes the GC content as the percentage of nucleotides that are `G` or `C` across the whole sequence: `100 * (count_G + count_C) / length`, rounded to 2 decimals (Python's built-in `round(x, 2)`).

Write `/app/biochem.txt` as exactly two lines:

```
complement:<uppercase complementary sequence>
gc_pct:<number>
```

For example, if the sequence were `AATT`, the output would be:
```
complement:TTAA
gc_pct:0.0
```

Run the script so `/app/biochem.txt` exists with the correct contents.