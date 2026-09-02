FROM bench-base:python-3.12

WORKDIR /app

# A local cache that mimics a single RCSB (PDB) fetch response for entry 3abc.
RUN mkdir -p /app/pip && cat > /app/pip/3abc.json <<'EOF'
{
  "rcsb_id": "3abc",
  "struct": {
    "title": "Sample protein",
    "n_residues": 12,
    "resolution": 2.1
  },
  "entities": [
    {"kind": "protein", "n_atoms": 120},
    {"kind": "water", "n_atoms": 18},
    {"kind": "ligand", "n_atoms": 6}
  ]
}
EOF

# A small helper that behaves like an "RCSB API" record fetch (offline stub).
RUN cat > /app/fetch_pdb.py <<'EOF'
import json

def fetch_pdb(pdb_id):
    """Return the RCSB-style structure record for a given PDB id."""
    with open(f'/app/pip/{pdb_id}.json') as f:
        return json.load(f)
EOF