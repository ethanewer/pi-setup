# drift-wharf — Zephyr toolchain build lab environment.
# Base: bench-base:ubuntu-24.04. We install the C/C++ toolchain used to (a)
# compile the Zephyr compiler itself from source, (b) act as the host C
# backend the Zephyr compiler drives, and (c) run the strict-C++11 probe.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gcc g++ make python3 file && \
    rm -rf /var/lib/apt/lists/*

# Scenario fixtures:
#   src/zephyr/   the Zephyr compiler source you build (from-scratch, clean-room)
#   deck/         the bundled Zephyr drift decoder (drift.zh) + runtime header (cardinal.h)
#   data/         the visible corpus (reference.txt)
#   probe/        the strict-C++11 probe consumer (probe.cpp)
# tests/ and solution/ are never copied into the image.
COPY files/ /app/

WORKDIR /app