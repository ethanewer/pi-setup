FROM bench-base:ubuntu-24.04

WORKDIR /app

# Headless vim for macro sourcing/verification, python3 for the verifier.
RUN apt-get update && apt-get install -y --no-install-recommends \
        vim python3 \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/
