FROM bench-base:ubuntu-24.04

# Kilnwatch gauge CLI bench for kiln-anchor: just the C toolchain.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
