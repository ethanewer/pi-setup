FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV OPAMROOT=/root/.opam

RUN apt-get update -qq && \
    apt-get install -y -qq \
        build-essential \
        g++ \
        gcc \
        cmake \
        clang \
        rustc \
        cargo \
        opam \
        bubblewrap \
        libgmp-dev \
        pkg-config \
        file \
        binutils \
        coreutils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

CMD ["/bin/bash"]