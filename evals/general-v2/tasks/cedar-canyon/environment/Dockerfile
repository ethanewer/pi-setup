FROM bench-base:ubuntu-24.04

WORKDIR /app

# Native build toolchain for the cedar-canyon math stack (offline-friendly).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential gcc g++ clang libomp-dev cmake make python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Sample workbench fixture (same schema as the hidden cases) so the agent can
# develop and self-test the stack locally.
COPY files/ /app/

WORKDIR /app