FROM bench-base:ubuntu-24.04

WORKDIR /app

# OCaml toolchain (agora bootstrap compiler incl OCaml runtime), C compiler, make
RUN apt-get update && apt-get install -y \
    ocaml \
    gcc \
    make \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

# generate the deterministic bootstrap stream (build step)
RUN cd /app && ocaml spec.ml

WORKDIR /app