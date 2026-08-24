#!/bin/bash
set -euo pipefail
cat > /app/analyze_dna.py <<'PY'
seq = open('/app/genome.txt').read().strip()
counts = {b: seq.count(b) for b in "ACGT"}
sub = seq[2:8]  # 0-based index 2, length 6
comp = {'A':'T','T':'A','C':'G','G':'C'}
revcomp = ''.join(comp[b] for b in reversed(sub))
with open('/app/dna_report.txt', 'w') as f:
    for b in "ACGT":
        f.write(f"{b} {counts[b]}\n")
    f.write(f"REVCOMP {revcomp}\n")
PY
python3 /app/analyze_dna.py