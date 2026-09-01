FROM bench-base:python-3.12

WORKDIR /app

# Toolchain needed at image-build time to compile the gatekeeper binary.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      gcc libc6-dev binutils \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# Compile the gatekeeper, strip it, and drop the source: only the binary ships.
RUN gcc -O1 -o /app/gatekeeper /app/gatekeeper.c \
 && strip /app/gatekeeper \
 && rm /app/gatekeeper.c \
 && chmod 0755 /app/gatekeeper
