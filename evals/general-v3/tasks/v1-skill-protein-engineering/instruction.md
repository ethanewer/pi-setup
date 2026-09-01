# Compute peptide molecular mass

A peptide is a short chain of amino acid residues joined by **peptide bonds**. Its total (monoisotopic) molecular mass is computed as:

```
peptide_mass = (sum of each amino-acid residue mass) + mass_of_water
```

where the `mass_of_water` term accounts for the water molecule released at the peptide's terminal (H + OH are added back at the chain ends). For this task use `mass_of_water = 18.01056` Da.

Monoisotopic residue masses (Da) for the residues you need:

| Residue | One-letter code | Mass (Da) |
|---------|-----------------|-----------|
| Alanine | A | 71.03711 |
| Cysteine | C | 103.00919 |
| Glutamic acid | E | 129.04259 |

Consider the peptide with the sequence **`ACE`** (one-letter codes read left to right: A, C, E).

Write a Python program `/app/peptide_mass.py` that computes the peptide's monoisotopic molecular mass using the residue masses above, and writes the result to `/app/molecule.json` as:

```json
{"peptide": "ACE", "mass_da": <mass value>}
```

Store the mass value as a float with full precision. Then run the program so `/app/molecule.json` exists.

The verifier recomputes the mass from the same residue-mass table and the peptide sequence, and checks it matches within `1e-3` Da.