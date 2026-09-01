FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# The nightly blob (200,000 bytes) is generated deterministically at build time.
RUN python3 /app/generate_blob.py /app/snapshots.blob 200000 \
    && rm /app/generate_blob.py
