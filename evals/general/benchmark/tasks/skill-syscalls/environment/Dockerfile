FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev strace \
    && rm -rf /var/lib/apt/lists/*

# 100-byte input file, compiled target binary
COPY files/prog.c /app/prog.c
RUN printf '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789' > /app/input.txt && \
    gcc -O0 -o /app/prog /app/prog.c