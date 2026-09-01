FROM bench-base:ubuntu-24.04
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
# toolchain for the serial/OpenMP/MPI builds plus the archiving steps
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc g++ make \
      cmake \
      libopenmpi-dev openmpi-bin \
      zstd \
      python3 \
      file \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# no fixtures are shipped; the agent authors the project from the spec