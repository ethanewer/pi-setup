FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev build-essential binutils \
    && rm -rf /var/lib/apt/lists/*

# Compile the target binary at build time.
COPY files/prog.c /app/src/prog.c
RUN gcc -O0 -o /app/prog /app/src/prog.c