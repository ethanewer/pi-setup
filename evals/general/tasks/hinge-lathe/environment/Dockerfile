FROM bench-base:ubuntu-24.04

WORKDIR /app

# Headless CLI tooling under test: vim (macro pass) and python3.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Shipped relay bulletin corpora (batch-1..3.txt).
COPY files/ /appdata/
