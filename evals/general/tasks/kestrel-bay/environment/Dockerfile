FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch for the gloo process group (no GPU in this image).
RUN pip install --no-cache-dir -q torch --index-url https://download.pytorch.org/whl/cpu

# Read-only fixture: the visible tide-gauge dataset.
COPY files/ /app/
RUN mkdir -p /app/data && mv /app/tide_gauge.csv /app/data/tide_gauge.csv
