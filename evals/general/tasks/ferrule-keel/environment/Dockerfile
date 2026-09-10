FROM bench-base:ubuntu-24.04

# Build toolchain for the agent's build, and the system reference compiler
# the verifier compares against. tcc bootstraps itself with gcc. No tcc
# package is installed anywhere: the only tcc that can exist in this image
# is the one the agent builds from /app/src.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc make git libc6-dev

# Allow the trial (root or uid 1000) to touch the root-owned clone, and give
# git a committer identity for the build-time patch commit below.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Real upstream tree, pinned to the immutable 40-hex commit. Shallow: the
# full tinycc history is not needed; the task is about building and using the
# compiler, not its archaeology.
ARG UPSTREAM_SHA=d348a9a51d32cece842b7885d27a411436d7887b
RUN git clone --depth 1 --branch release_0_9_27 \
        https://github.com/TinyCC/tinycc.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

WORKDIR /app

COPY files/ /app/

# glibc 2.34+ removed the __malloc_hook ABI that bcheck.c's bounds checker
# used at 0.9.27, so a stock 0.9.27 tree cannot complete its own default
# build on this base image. Apply the small authored compat patch (see
# bcheck-glibc.patch) and commit it so the tree is clean and reproducibility
# does not depend on the working tree. Then guarantee write access for
# whatever uid (root or 1000) the trial runs as.
RUN git -C /app/src apply /app/bcheck-glibc.patch \
 && git -C /app/src add lib/bcheck.c \
 && git -C /app/src commit -q -m "build: drop removed glibc malloc hooks in bcheck (bcheck-glibc.patch)" \
 && chmod -R a+rwX /app \
 && rm -f /app/bcheck-glibc.patch \
 && echo "build-ok"