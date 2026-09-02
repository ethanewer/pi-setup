FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y g++ libc6-dev && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /app/found

# Compile the oracle:: the real 16-bit key (0x9E4C) is injected at build time
# via ORACLE_KEY so the source alone does not reveal it.
COPY files/ /app/
RUN g++ -std=c++17 -O2 -DORACLE_KEY=0x9E4C -o /app/candle /app/candle.c