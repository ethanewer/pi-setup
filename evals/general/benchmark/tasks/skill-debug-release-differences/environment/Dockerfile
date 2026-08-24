FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libc6-dev build-essential && rm -rf /var/lib/apt/lists/*

# A single C source that behaves differently in a debug build (assertions on)
# vs a release build (compiled with -DNDEBUG). Currently the debug build
# aborts on negative input while the release build silently clamps it.
COPY files/calc.c /app/calc.c
