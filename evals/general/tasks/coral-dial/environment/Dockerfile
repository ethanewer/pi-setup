FROM bench-base:python-3.12

WORKDIR /app

# numpy for fixtures/arrays, CPU-only torch for the sharded layer.
RUN pip install --no-cache-dir -q numpy && \
    pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only visible fixture: the serving geometry config.
COPY files/ /app/
