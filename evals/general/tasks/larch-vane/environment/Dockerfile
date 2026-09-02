FROM bench-base:ubuntu-24.04

# Field-station deployment pipeline bench for larch-vane.
# Shipped with the three-stage reduction pipeline deliberately stripped of
# executable bits and a tree listing that must stay byte-for-byte intact.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 ca-certificates findutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
# Pristine byte copies used by the verifier to detect content tampering.
COPY files/pipeline/ingest.sh  /opt/pristine/ingest.sh
COPY files/pipeline/enrich.sh  /opt/pristine/enrich.sh
COPY files/pipeline/publish.sh /opt/pristine/publish.sh
COPY files/tree-listing.txt    /opt/pristine/tree-listing.txt

# Ship the pipeline scripts WITHOUT executable bits (the competency).
RUN chmod 0644 /app/pipeline/ingest.sh /app/pipeline/enrich.sh /app/pipeline/publish.sh
