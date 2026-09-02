FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc g++ cmake make zstd python3 binutils \
 && rm -rf /var/lib/apt/lists/*
