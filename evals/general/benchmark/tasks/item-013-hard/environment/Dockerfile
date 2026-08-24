FROM bench-base:ubuntu-24.04

WORKDIR /app

# The image ships only gcc + make. The OCaml/Coq toolchain is intentionally
# absent: the agent must probe (./configure) and install them.
RUN apt-get update && apt-get install -y gcc libc6-dev make && rm -rf /var/lib/apt/lists/*

COPY files/cc-src/ /app/cc-src/