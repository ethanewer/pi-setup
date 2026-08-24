FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y g++ libc6-dev && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/data/x && \
    printf 'abc' > /app/data/a.log && \
    printf 'hello' > /app/data/b.log && \
    printf 'world!' > /app/data/x/c.txt && \
    : > /app/data/x/empty.txt