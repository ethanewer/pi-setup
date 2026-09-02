FROM bench-base:ubuntu-24.04
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive

# toolchain: debug the release-mode pool crash (gcc, gdb), verify with python3
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc make gdb binutils libc6-dev \
      python3 \
      file ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Ship the (crashing) bench sources; the agent fixes forge.c only.
COPY files/ /app/

# Build the release binary the agent must repair.
RUN make -C /app
