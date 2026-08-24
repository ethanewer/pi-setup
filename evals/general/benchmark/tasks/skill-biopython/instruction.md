`/app/sequences.fasta` is a FASTA file with three DNA records, each named `seqA`, `seqB`, and `seqC`. Use the **Biopython** library (`Bio.SeqIO`) to parse it.

Write a program `/app/analyze.py` that:
1. parses `/app/sequences.fasta` with `Bio.SeqIO`,
2. for every record computes:
   - `length`: the number of characters in its DNA sequence,
   - `counts`: a dict of nucleotide counts for A, C, G, T (always include all four keys, even when 0),
   - `gc_pct`: the percentage of nucleotides that are G or C among the sequence's total length, rounded to 2 decimal places,
3. writes `/app/summary.json` as a JSON list, in file order, of objects:
   `{"id": "...", "length": N, "counts": {"A":n,"C":n,"G":n,"T":n}, "gc_pct": x.xx}`

Run your program so `/app/summary.json` is produced. The verifier uses the same biopython parsing.
