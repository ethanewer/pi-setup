# DHFR drug-candidate analysis: molecular formula from SMILES

Dihydrofolate reductase (DHFR) is a classic drug-design target, and DHFR
benchmark suites describe candidate inhibitor molecules with **SMILES** strings.

`/app/candidate.smi` contains a single SMILES line for one such small candidate
molecule (a simple linear chain; no rings, no branches, no brackets):

```
CCCCO
```

## Task

Write a Python 3 script `/app/formula.py` that reads `/app/candidate.smi`,
counts the **heavy atoms** (all atoms except Hydrogen) of each element present
in the molecule, and writes the counts to `/app/formula.txt`.

### SMILES rules you must apply

A SMILES string is a sequence of atom symbols separated by bond/format tokens
(`-`, `=`, `#`, `.`, digits, parentheses). To count heavy atoms:

- An atom symbol is an uppercase letter optionally followed by one lowercase
  letter (e.g. `C`, `N`, `O`, `S`, `P`, `F`, `Cl`, `Br`).
- Elements that may appear in this molecule: `C`, `N`, `O`, `S`, `P`, `F`,
  `Cl`, `Br`. Hydrogen is **never counted** (it is implicit in SMILES).
- All other tokens are ignored.

### Output format

Write exactly 8 lines to `/app/formula.txt`, one per element in this fixed
order, each line `SYMBOL count` (single space):

```
C 4
N 0
O 1
S 0
P 0
F 0
Cl 0
Br 0
```

(For `CCCCO` the molecule is butanol, formula C4H10O: 4 carbons, 1 oxygen,
and zero of every other heavy element.)

You may verify your own result with a quick sanity check: a line of `n`
uppercase `C`s contributes `n` to the C count.

The verifier checks that `/app/formula.txt` exists and contains exactly these
eight counts.
