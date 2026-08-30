FROM bench-base:python-3.12

# R is the toolchain of the consumer's plug-in contract.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends r-base-core && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

CMD ["/bin/bash"]
