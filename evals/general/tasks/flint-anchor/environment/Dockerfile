FROM bench-base:ubuntu-24.04

WORKDIR /app

# Lean toolchain for the flint project: C/C++ compilers, binutils (as/ld/
# readelf), make, and python3 (already present on the base). Everything the
# five subsystems need is available headlessly; no GPU/X/systemd required.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    gcc g++ binutils make python3 \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# The verifier writes its reward here.
RUN mkdir -p /logs/verifier && chmod -R a+r /app
