FROM bench-base:ubuntu-24.04

WORKDIR /app

# OCaml runtime + C toolchain + pytest
RUN apt-get update && apt-get install -y \
    ocaml \
    gcc \
    make \
    build-essential \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install -q --break-system-packages pytest

COPY files/ /app/

# generate the deterministic bootstrap stream (build step)
RUN cd /app && ocaml spec.ml

WORKDIR /app