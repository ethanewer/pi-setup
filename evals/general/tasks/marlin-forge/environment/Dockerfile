FROM bench-base:python-3.12

WORKDIR /app

# C toolchain for the shared-heap (pthread/UPC-style) assembly deliverable.
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

CMD ["/bin/bash"]
