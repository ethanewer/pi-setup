FROM bench-base:python-3.12

# Unframework parsing + numeric stack for the reconciliation deliverable.
RUN pip install --no-cache-dir numpy pyarrow

WORKDIR /app
COPY files/ /app/