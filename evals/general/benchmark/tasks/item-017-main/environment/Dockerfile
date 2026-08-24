FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y \
    p7zip-full john \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/vault.7z /app/vault.7z