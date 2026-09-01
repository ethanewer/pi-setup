FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

# Toolchain for building the native scorer binary, plus file(1) for ELF checks.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      gcc libc6-dev make file ca-certificates >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "moss-vane: apt install complete"

WORKDIR /app

# Visible smoke fixtures (the instruction tells the agent not to modify these).
COPY files/weights.txt /app/fixtures/weights.txt
COPY files/image.pgm   /app/fixtures/image.pgm

CMD ["/bin/bash"]
