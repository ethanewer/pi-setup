FROM bench-base:ubuntu-24.04

WORKDIR /app

# C build toolchain.
RUN apt-get update && apt-get install -y gcc libc6-dev make binutils && rm -rf /var/lib/apt/lists/*

# Legacy pMARS (Core War simulator) source package, extracted to /app/pmars-src/.
COPY files/pmars-src.tar.gz /app/
RUN mkdir -p /app/pmars-src && tar -xz -C /app/pmars-src -f /app/pmars-src.tar.gz

# Tournament harness, visible opponents, and legacy build instructions.
COPY files/tournament /app/tournament