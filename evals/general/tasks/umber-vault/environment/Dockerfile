FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch (no CUDA), plus the data/ML stack used by the pipeline and the
# verifier. scikit-learn is pulled for the documented stack even though the core
# deliverable scripts rely on numpy/pandas/torch only.
RUN pip install --no-cache-dir numpy pandas scikit-learn \
 && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Architecture constant shared by every component (must match the verifier).
ENV UMBER_FEATURES=48 UMBER_HIDDEN=64 UMBER_CLASSES=2

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the provided datasets inside /app/data at build time, then remove
# the generator (and any stray bytecode) so the concrete data-generation rule is
# not discoverable inside the live container.
RUN python3 /app/gen_data.py && rm -f /app/gen_data.py && rm -rf /app/__pycache__

# The agent must never find tests/ or solution/ inside the image.