FROM bench-base:node-22

ENV DEBIAN_FRONTEND=noninteractive

# gcc for building the native engine binary; node + python3 already in base.
RUN apt-get update >/dev/null 2>&1 && \
    apt-get install -y --no-install-recommends \
      gcc libc6-dev file ca-certificates >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/* && \
    echo "hazel-latch: apt install complete"

WORKDIR /app

# Immutable lab inputs: the external launcher and a sample session.
COPY files/launcher.mjs /app/launcher.mjs
COPY files/session.txt  /app/samples/session.txt

CMD ["/bin/bash"]
