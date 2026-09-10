FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

RUN apt-get update -qq && \
    apt-get install -y -qq \
        golang-go \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/
