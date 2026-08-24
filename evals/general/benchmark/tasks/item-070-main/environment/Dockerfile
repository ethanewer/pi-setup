FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build toolchain: gcc/g++ libc6-dev (gcov ships with gcc), make, and autotools.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential autoconf automake libtool \
 && rm -rf /var/lib/apt/lists/*

# Vendored SQLite source release tarball (SQLite 3.46.1, autotools layout).
# The agent must extract/build this exact tarball; the tarball stays in the
# image so its SHA-256 can be re-verified later.
COPY files/ /app/src/

# QA smoke corpus the agent runs against the freshly built sqlite3 shell.
RUN mkdir -p /app/data /app/artifacts \
 && mv /app/src/corpus.sql /app/data/corpus.sql
