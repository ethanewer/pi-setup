FROM bench-base:ubuntu-24.04

WORKDIR /app

# Build toolchain: gcc/g++ libc6-dev (gcov ships with gcc), make, and autotools needed to
# regenerate configure from configure.ac (no pre-generated configure shipped).
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential autoconf automake libtool \
 && rm -rf /var/lib/apt/lists/*

# Vendored SQLite 3.46.1 autotools source release with the pre-generated
# configure scripts deliberately removed (`configure`, `tea/configure`).
COPY files/ /app/src/

# QA smoke corpus + CSV fixture for .import testing.
RUN mkdir -p /app/data /app/artifacts \
 && mv /app/src/corpus-hard.sql /app/data/corpus-hard.sql \
 && mv /app/src/import.csv /app/data/import.csv