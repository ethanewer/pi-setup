FROM bench-base:python-3.12

WORKDIR /app

# numpy for the fixtures, CPU-only torch for the pooling module.
RUN pip install --no-cache-dir -q numpy && \
    pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only visible fixture: the LiDAR cluster config and catalog.
COPY files/ /app/
