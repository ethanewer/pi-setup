FROM bench-base:python-3.12

WORKDIR /app

# Deterministic replay eval of a trained CPU policy: torch (CPU wheel) + numpy.
RUN pip install --no-cache-dir --quiet \
        numpy && \
    pip install --no-cache-dir --quiet \
        torch --index-url https://download.pytorch.org/whl/cpu

# Read-only fixture: the rover case (env config + trained checkpoint).
COPY files/ /app/
