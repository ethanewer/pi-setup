# wren-link — Skerry plugin SDK (IR coalescing) environment.
# LLVM/clang toolchain; the per-module IR fixtures are emitted from the shipped
# C sources at build time with the exact system toolchain the verifier uses.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends clang llvm-18 && \
    rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# Bake the shipped per-module IR from the locked C sources (deterministic),
# and a reference ELF build the agent may compare against (not required).
RUN for m in gain envelope limiter; do \
      clang-18 -O0 -emit-llvm -c /app/src/$m.c -o /app/src/$m.ll ; \
    done && \
    chmod -R a+rX /app

WORKDIR /app
