FROM bench-base:python-3.12
WORKDIR /app

# ML toolchain used by the deliverable (torch for chess state-dict build) and by
# the fixtures (numpy recompute the extraction probes). CPU-only.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch==2.13.0 \
    numpy \
    scipy \
    scikit-learn

COPY files/ /app/