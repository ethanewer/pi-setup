# Reverse complements of DNA sequences

`/app/data.json`:

```json
{"sequences": ["ACGT", "AATG", "GGTT", "GATTACA"]}
```

Write `/app/revcomp.py` that, for each sequence, computes its **reverse complement**:
reverse the sequence, then replace every base by its complement
(`A`↔`T`, `C`↔`G`), preserving case. Sequences are valid uppercase DNA only.

Write `/app/result.json`:

```json
{"complements": ["ACGT", "CATT", "AACC", "TGTAATC"]}
```

Run `python3 /app/revcomp.py` so the file is produced. The verifier recomputes the
reverse complement of each sequence; do not hardcode.