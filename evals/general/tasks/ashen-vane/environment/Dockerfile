FROM bench-base:ubuntu-24.04
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
# toolchain for authoring + compiling the native edgecheck binary
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev make file python3 \
    && rm -rf /var/lib/apt/lists/*
# no fixtures are shipped; the agent authors the program from the spec
