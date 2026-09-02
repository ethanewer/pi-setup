FROM bench-base:ubuntu-24.04

WORKDIR /app

# GNU Privacy Guard for the symmetric-archive stage (AES-256 via --cipher-algo
# AES256; man gpg documents the strongest option).  No extras: everything else
# is stdlib python3 + a shell.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnupg \
        coreutils \
        tar \
        gzip \
        grep \
        sed \
        findutils \
        man-db \
 && rm -rf /var/lib/apt/lists/*

# Scenario fixtures: detection logs (2 files), the symmetric-passphrase stash,
# the cleartext oracle service, and the queue consumer worker.
COPY files/ /app/

# Public-facing artifacts an operator ships; plaintext transient archives live
# only under /tmp and are removed by encrypt.sh.
ENV LC_ALL=C.UTF-8

CMD ["/bin/bash"]