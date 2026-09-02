FROM bench-base:ubuntu-24.04

# gcc + python3 (ziplib) + openssl for the oracle and verification steps.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        python3 \
        openssl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/