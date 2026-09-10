FROM bench-base:python-3.12

# C toolchain and git (no network exists during the trial; everything the agent
# or the verifier needs must be baked in at build time).
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git \
 && rm -rf /var/lib/apt/lists/*

# Upstream repository, pinned to the exact commit this task was built against.
# nothings/stb: single-header C library (stb_image.h / stb_image_write.h).
# A tag alone could be force-moved upstream; assert the full 40-hex commit so
# the build fails closed if upstream ever changes under us.
ARG UPSTREAM_SHA=2c980bb59875b0d32144a71867fbdebb2f77cd20
RUN git clone --depth 1 https://github.com/nothings/stb.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app

# Agent workspace: samples + the two headers live in /app/src; fixtures land at
# /app/fixtures.  Make /app writable no matter which user the trial runs as.
RUN chmod 1777 /app

COPY files/ /app/