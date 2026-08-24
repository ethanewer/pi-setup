#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
seq = open('/app/genome.txt').read().strip()
counts = {b: seq.count(b) for b in "ACGT"}
sub = seq[2:8]
comp = {'A':'T','T':'A','C':'G','G':'C'}
revcomp = ''.join(comp[b] for b in reversed(sub))
expected = "".join(f"{b} {counts[b]}\n" for b in "ACGT") + f"REVCOMP {revcomp}\n"

got = open('/app/dna_report.txt').read()
assert got == expected, (got, expected)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt