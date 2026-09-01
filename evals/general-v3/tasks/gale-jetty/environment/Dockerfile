FROM bench-base:python-3.12

WORKDIR /app

# Data tooling for the pipeline (csv/json/parquet parsing + numpy matrices).
RUN python -m pip install --no-cache-dir numpy pandas pyarrow

COPY files/ /app/.fixtures/

# Materialize the working fixtures (inbox docs, masks, heterogeneous ledger,
# candidates, config, sequential constant) directly into /app.
RUN python3 /app/.fixtures/build_fixtures.py && rm -rf /app/.fixtures

WORKDIR /app