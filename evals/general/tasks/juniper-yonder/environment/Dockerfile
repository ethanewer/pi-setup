FROM bench-base:python-3.12

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/

# Compile the chosen-plaintext oracle for the shipped scenario.
# The low-bit round keys (YK0/YK1) are baked in at build time and are NOT
# present in any source file an agent can read.
RUN gcc -O2 -o /app/workspace/yonder_enc /app/workspace/oracle.c \
        -DYK0=0xe7 -DYK1=0xee

CMD ["/bin/bash"]
