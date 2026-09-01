# quartz-summit - small-scale ML training harness (CPU-only).
FROM bench-base:python-3.12
WORKDIR /app

# ML toolchain used by the deliverable (torch for the 300-dim embedding layer)
# and by the verifier (numpy recomputes the STS / edge expectations). CPU only.
RUN pip install --no-cache-dir --disable-pip-version-check \
    torch \
    numpy \
    scipy \
    scikit-learn

COPY files/ /app/
