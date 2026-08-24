FROM bench-base:ubuntu-24.04

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/cullet.c /tmp/cullet_src.c
RUN gcc -O2 -o /app/cullet /tmp/cullet_src.c && rm -f /tmp/cullet_src.c