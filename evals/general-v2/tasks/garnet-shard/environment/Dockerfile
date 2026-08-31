FROM bench-base:ubuntu-24.04
WORKDIR /app

# gcc for building the delivered recovery program; the artifacts are the
# appliance's exported breach evidence.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*

COPY files/artifacts /app/artifacts/
RUN chown -R root:root /app/artifacts && chmod -R a-w /app/artifacts

CMD ["/bin/bash"]
