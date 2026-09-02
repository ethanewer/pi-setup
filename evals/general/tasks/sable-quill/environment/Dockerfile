FROM bench-base:ubuntu-24.04
WORKDIR /app

# R is the toolchain of the delivered module (base + stats only).
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends r-base && \
    rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
