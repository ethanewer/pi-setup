FROM bench-base:ubuntu-24.04

# The base image may lack a C compiler; install one.
RUN apt-get update && apt-get install -y gcc libc6-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/src /app/src

# Build the oracle decoder and the encoder from source.
RUN gcc -O2 -o /app/decompress /app/src/decompress.c \
 && gcc -O2 -o /app/enc /app/src/enc.c

# Build the PUBLIC reverse-engineering corpus: plaintext + its compression.
RUN mkdir -p /app/corpus && \
 cp /app/src/seed/c1.txt /app/corpus/c1.txt && /app/enc /app/corpus/c1.txt /app/corpus/c1.bin && \
 cp /app/src/seed/c2.txt /app/corpus/c2.txt && /app/enc /app/corpus/c2.txt /app/corpus/c2.bin && \
 cp /app/src/seed/c3.txt /app/corpus/c3.txt && /app/enc /app/corpus/c3.txt /app/corpus/c3.bin && \
 cp /app/src/seed/c4.txt /app/corpus/c4.txt && /app/enc /app/corpus/c4.txt /app/corpus/c4.bin && \
 cp /app/src/seed/c5.txt /app/corpus/c5.txt && /app/enc /app/corpus/c5.txt /app/corpus/c5.bin

# Build HIDDEN streams; their plaintext seeds never survive into the image.
RUN mkdir -p /app/hidden && \
 /app/enc /app/src/hseed/h1.txt /app/hidden/h1.bin && \
 /app/enc /app/src/hseed/h2.txt /app/hidden/h2.bin && \
 /app/enc /app/src/hseed/h3.txt /app/hidden/h3.bin && \
 /app/enc /app/src/hseed/h4.txt /app/hidden/h4.bin && \
 /app/enc /app/src/hseed/h5.txt /app/hidden/h5.bin && \
 /app/enc /app/src/hseed/h6.txt /app/hidden/h6.bin && \
 /app/enc /app/src/hseed/h7.txt /app/hidden/h7.bin

# Remove C sources so the format must be inferred from executable behavior.
RUN rm -rf /app/src