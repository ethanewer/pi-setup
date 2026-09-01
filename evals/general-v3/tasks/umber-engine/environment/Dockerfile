FROM bench-base:node-22
WORKDIR /app
# Build toolchains the agent needs to author and the verifier needs at run time.
RUN apt-get update && apt-get install -y --no-install-recommends \
    rustc cargo clang lld python3-pip \
  && rm -rf /var/lib/apt/lists/*
# Python runtime dependencies: WebAssembly runtime for the memory probe, and the
# grpc python toolchain (library + code generator) installed system-wide.
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    wasmtime grpcio grpcio-tools
COPY files/ /app/