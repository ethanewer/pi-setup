# kite-yonder benchmark environment.
# The whole native C/C++ stack runs in one container: gcc, clang, cmake, make,
# and libomp. No GPU/systemd/X.
FROM bench-base:ubuntu-24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential g++ clang cmake make gcc libomp-dev llvm \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/