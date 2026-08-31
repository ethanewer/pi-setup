FROM bench-base:ubuntu-24.04

WORKDIR /app

# GNU Privacy Guard for the symmetric seal (AES256 via --cipher-algo, SHA512
# S2K via --s2k-digest-algo; man gpg documents the options). Everything else
# is a stock shell + tar/gzip/coreutils toolchain.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gnupg \
        tar \
        gzip \
        coreutils \
        findutils \
        man-db \
 && rm -rf /var/lib/apt/lists/*

# Scenario fixtures: the evidence tree and the passphrase stash.
COPY files/ /app/

ENV LC_ALL=C.UTF-8

CMD ["/bin/bash"]
