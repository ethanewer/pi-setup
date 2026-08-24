FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev make binutils && rm -rf /var/lib/apt/lists/*

COPY files/pmars-src.tar.gz /app/
RUN mkdir -p /app/pmars-src && tar -xz -C /app/pmars-src -f /app/pmars-src.tar.gz

COPY files/tournament /app/tournament