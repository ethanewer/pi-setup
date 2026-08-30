FROM bench-base:python-3.12

WORKDIR /app

# RDKit is required for the SMILES-conversion deliverable and the verifier.
RUN pip install --no-cache-dir -q rdkit

COPY files/ /app/

# The localhost mock API server + the two FASTA templates in /app are read-only
# fixtures; deliverables must live under /app alongside them.