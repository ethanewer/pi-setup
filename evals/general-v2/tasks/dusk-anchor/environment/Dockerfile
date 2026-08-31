# dusk-anchor: standalone C reimplementation of a recovered byte transform.
#
# Base: python-3.12 + the C toolchain needed to build a static binary and to
# let the verifier check linkage (gcc, make, binutils, file). The recovery work
# itself happens at agent runtime; the image ships only the behavior spec and
# the seed fixture.
FROM bench-base:python-3.12

WORKDIR /app

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential gcc make binutils file \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fixtures shipped in the image (do not modify):
#   /app/vellum-spec.txt - the recovered-behavior contract
#   /app/seed.bin        - fixed input the agent's proof digest is taken over
COPY files/ /app/

CMD ["/bin/bash"]
