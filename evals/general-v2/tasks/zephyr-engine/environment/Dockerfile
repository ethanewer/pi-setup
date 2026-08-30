FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    p7zip-full \
    openssl \
    john \
    python3 \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/
