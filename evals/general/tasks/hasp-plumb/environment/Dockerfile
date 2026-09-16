# hasp-plumb: build the real Redis server from source and operate it.
#
# The upstream tree is cloned here, at image-build time (no network exists at
# trial time), shallow and pinned to the immutable 40-hex commit that was
# resolved for tag 8.10.1 on the authoring date. The pin assertion makes the
# build fail closed if the tag were ever force-moved upstream, so the image
# always reproduces the tree that was measured.
#
# The compile step is deliberately NOT done here: building the server is the
# agent's job (this slot is redis-build-operate, and at 1 CPU the build takes
# about two minutes, comfortably inside the agent budget). Build tooling is
# installed here so the agent only has to run `make`.

ARG UPSTREAM_SHA=3399357e7c17b668289386b8a15a3037bc4527b1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=3399357e7c17b668289386b8a15a3037bc4527b1

# Toolchain for the C build: gcc, make, plus git for the clone. Shut down clean.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git build-essential coreutils procps \
 && rm -rf /var/lib/apt/lists/*

# Real upstream Redis 8.10.1, shallow clone pinned to the 40-hex commit.
RUN git clone --depth 1 --branch 8.10.1 https://github.com/redis/redis.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app

COPY files/ /app/

# Whatever uid the trial runs as (root or 1000), it must be able to write
# build artefacts into /app/src and runtime data into /app/data.
RUN chmod -R a+rwX /app \
 && mkdir -p /app/data \
 && chown -R 1000:1000 /app 2>/dev/null || true \
 && echo "build-ok"