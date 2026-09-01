FROM bench-base:python-3.12
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

# Toolchain for the agent: python3 is in the base; gcc/objdump allow
# observation-driven and disassembly-driven reverse engineering of the target.
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev binutils \
    && rm -rf /var/lib/apt/lists/*

# Visible fixture frame for the agent to probe against.
COPY files/ /app/

# Build-context-only source for the native target (removed after build).
COPY aux/ /aux/

RUN mkdir -p /app/target && \
    gcc -O2 -o /app/target/pixelcast /aux/pixelcast.c && \
    strip /app/target/pixelcast && \
    rm -rf /aux && \
    chmod 0755 /app/target/pixelcast && \
    chmod 0444 /app/fixture.ppm
