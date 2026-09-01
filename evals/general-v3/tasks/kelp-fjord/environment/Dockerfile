FROM bench-base:ubuntu-24.04

WORKDIR /app

# GNU Privacy Guard for the symmetric seal stage (AES-256 via --cipher-algo
# AES256, discovered through `man gpg`). No extras beyond coreutils/tar/gzip.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnupg \
        coreutils \
        tar \
        gzip \
        findutils \
        man-db \
 && rm -rf /var/lib/apt/lists/*

# Scenario fixtures: the clinical export tree and the passphrase file.
COPY files/ /app/

ENV LC_ALL=C.UTF-8

CMD ["/bin/bash"]
