# slate-ratchet: Garnet Vault crackme environment
FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Prebuild the reference checker shipped with the release image.
RUN gcc -O2 -o /app/src/vault /app/src/vault.c
