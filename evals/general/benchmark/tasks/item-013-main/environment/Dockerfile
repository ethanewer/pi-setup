FROM bench-base:ubuntu-24.04

WORKDIR /app

# Only the C compiler + make are preinstalled. The OCaml and Coq toolchain
# components are intentionally absent; the agent diagnoses and installs them.
RUN apt-get update && apt-get install -y gcc libc6-dev make && rm -rf /var/lib/apt/lists/*

COPY files/compcert-src/ /app/compcert-src/