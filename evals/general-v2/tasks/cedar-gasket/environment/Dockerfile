FROM bench-base:python-3.12

WORKDIR /app

# numpy + rdkit from the default index, then CPU-only torch from the PyTorch
# CPU wheel index (no GPU in this image; the #nn module only needs CPU ops).
RUN pip install --no-cache-dir -q numpy rdkit && \
    pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only fixtures: the word-relation vocabulary and the molecule catalog.
COPY files/ /app/

# Deliverables (created by the agent) live under /app alongside these fixtures.