# DNA sequence analysis: nucleotide counts and reverse complement

`/app/genome.txt` contains a single DNA sequence (uppercase letters from
`A`, `C`, `G`, `T`), e.g.:

```
ACGTTGCAATGCCGTA
```

## Task

Write a Python 3 script `/app/analyze_dna.py` that reads `/app/genome.txt`
and writes `/app/dna_report.txt` with two kinds of results.

### 1. Nucleotide counts

Count how many times each nucleotide occurs in the whole sequence, one line
per nucleotide in the fixed order `A`, `C`, `G`, `T`:

```
A 4
C 4
G 4
T 4
```

### 2. Reverse complement of a substring

Take the substring of the genome that starts at **0-based index 2** and
has **length 6** (i.e. positions `2..7` inclusive). Compute its **reverse
complement**:

1. Reverse the substring (last character first).
2. Complement each base: `A <-> T`, `C <-> G`.

Write it on the final line:

```
REVCOMP TGCAAC
```

### Output file

`/app/dna_report.txt` must have exactly 5 lines:

```
A 4
C 4
G 4
T 4
REVCOMP TGCAAC
```

The verifier recomputes both the counts and the reverse complement from the
provided genome file and compares every line.