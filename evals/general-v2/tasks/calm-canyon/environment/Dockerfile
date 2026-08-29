FROM bench-base:ubuntu-24.04

# hydrawatch: source restore -> scoped Maven rebuild (REST service on a local
# port), a Lean lake project pulling a small math library, and Python bindings
# generated from a .proto. Everything is offline-capable after first setup.

ENV DEBIAN_FRONTEND=noninteractive
ENV ELAN_HOME=/root/.elan
ENV PATH=/root/.elan/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## 1) base toolchain
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
        git curl ca-certificates \
        maven openjdk-17-jdk-headless \
        python3 python3-pip \
        elan \
 && rm -rf /var/lib/apt/lists/*

# 2) Lean toolchain via elan (used by the lake project)
RUN elan toolchain install stable && elan default stable \
 && lean --version && lake 2>/dev/null | head -1 || true

# 3) Python binding toolchain (grpc / protobuf code generators + client runtime)
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        grpcio grpcio-tools protobuf >/dev/null 2>&1 || \
    python3 -m pip install --no-cache-dir --break-system-packages grpcio grpcio-tools protobuf

# 4) fixtures: the release object store, the bundled math library, helpers
COPY files/ /app/
WORKDIR /app

# sanity: the visible release store is present
RUN test -n "$(cat /app/payload/current.txt)" \
 && test -s /app/payload/hydrawatch-src-2029.55.0.tgz \
 && echo "payload ok"