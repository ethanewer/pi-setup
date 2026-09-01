FROM bench-base:python-3.12

# gcc/libc-dev are needed ONLY at image build time, to compile the native
# reverse-engineering target from the build-context-only aux source. The
# source is removed from the final image; no network is used at run/verify.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

# Build the compiled scene target the agent must reverse-engineer, then drop
# the source so it ships only as a stripped binary.
COPY aux/ /aux/
RUN mkdir -p /app/target \
 && gcc -O2 -s -o /app/target/raycaster /aux/raycaster.c \
 && rm -rf /aux \
 && chmod 0755 /app/target/raycaster

CMD ["bash"]
