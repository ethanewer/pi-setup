#!/usr/bin/env python3
"""Convert SMILES strings to RDKit Mol objects, returning None for invalid or
empty input instead of raising.

Contract:
    python3 /app/smiles.py <catalog.json> <report.json>

<catalog.json> maps an arbitrary sample id -> a SMILES string (may contain
empty/whitespace and malformed values). The script writes <report.json> as a
JSON object mapping each sample id to either:
    {"valid": true, "atoms": <N>}   for a non-empty, parse-able SMILES
    null                            for an invalid or empty/whitespace-only SMILES
It must NEVER raise or exit non-zero on any input; a malformed string yields
null in the report. The module also exposes a reusable convert() function.
"""

import json
import sys

from rdkit import Chem, RDLogger

RDLogger.DisableLog("rdApp.*")


def convert(smiles):
    """Return an RDKit Mol for a non-empty, valid SMILES, else None.

    Empty or whitespace-only input is treated as invalid (returns None), even
    though RDKit's MolFromSmiles would return an empty Mol object for "".
    """
    if not isinstance(smiles, str):
        return None
    if not smiles.strip():
        return None
    try:
        return Chem.MolFromSmiles(smiles)
    except Exception:
        return None


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: smiles.py <catalog.json> <report.json>\n")
        return 2
    in_path, out_path = argv[1], argv[2]
    with open(in_path) as fh:
        catalog = json.load(fh)
    report = {}
    if isinstance(catalog, dict):
        for sid, smi in catalog.items():
            mol = convert(smi)
            report[sid] = (None if mol is None
                           else {"valid": True, "atoms": mol.GetNumAtoms()})
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))