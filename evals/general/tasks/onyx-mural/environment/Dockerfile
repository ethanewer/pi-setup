FROM bench-base:ubuntu-24.04
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

# Toolchain: reverse-engineer the native target (objdump/gdb/strings), plus
# python3 for the reimplementation deliverable.
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev make binutils gdb file python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Visible sample grids for probing.
COPY files/ /app/

# Build-context-only source for the native fixture (removed after build).
COPY aux/ /aux/

# Build the reverse-engineering target; the source must not ship.
RUN mkdir -p /app/scene && \
    gcc -O2 -o /app/scene/mural /aux/mural.c && \
    rm -rf /aux && \
    chmod 0755 /app/scene/mural
