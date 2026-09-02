FROM bench-base:ubuntu-24.04

WORKDIR /app

# tar + p7zip for the archive and extraction tasks, python3 for the tooling.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      tar p7zip-full python3 \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# Build the password-encrypted 7z archive deterministically from the raw
# payload, using the on-disk recovered credential; drop the raw plaintext.
RUN cd /app/raw \
 && PW="$(cat /app/credentials/key.txt)" \
 && 7z a -bd -y -p"$PW" /app/vault.7z payload_secret.txt >/dev/null \
 && cd / && rm -rf /app/raw

WORKDIR /app