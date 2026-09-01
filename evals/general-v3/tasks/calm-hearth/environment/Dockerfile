FROM bench-base:ubuntu-24.04
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

# toolchain: debug the C heap (gcc/g++/gdb/valgrind), FFI via ctypes (python3),
# disassembly/observation for the native target (binutils objdump, clang).
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ make gdb \
      binutils clang \
      python3 \
      valgrind \
      file ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ship the (buggy) custom-heap sources for the agent to fix.
COPY files/heap/ /app/

# Build-context-only sources for the native fixtures (removed after build).
COPY aux/ /aux/

# Build the two native fixtures that must NOT ship as source:
#   /app/libtransform.so - the FFI library
#   /app/target/render   - the reverse-engineering target binary
RUN mkdir -p /app/target && \
    gcc -O2 -fPIC -shared -o /app/libtransform.so /aux/transform.c && \
    gcc -O2 -o /app/target/render /aux/render.c && \
    rm -rf /aux && \
    chmod 0755 /app/target/render && \
    chmod 0644 /app/libtransform.so