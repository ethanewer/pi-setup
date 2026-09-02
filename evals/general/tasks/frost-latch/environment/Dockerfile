FROM bench-base:python-3.12
ENV DEBIAN_FRONTEND=noninteractive
# Toolchain for building the shelf scanner from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev make python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# No fixtures shipped: the agent authors the C source, Makefile and binary.
