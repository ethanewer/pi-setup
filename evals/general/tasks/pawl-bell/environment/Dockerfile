# pawl-bell: upstream-clone chess-engine task on official-stockfish/Stockfish
#
# The upstream repository is cloned, SHA-pinned and left unbuilt at build time
# (network exists while the image builds). The trial runs with no network, so
# everything the task needs is already in this image: the pinned checkout at
# /app/src and the g++/make toolchain. The agent must build the engine with the
# project's own Makefile (single-threaded; measured ~40s on one core) and write
# a UCI protocol driver at /app/uci_play.py.
#
# No pip/npm/gradle caches to warm: the agent's whole job is the one make
# build plus a small protocol driver, and Stockfish compiles fully offline.

FROM bench-base:ubuntu-24.04

# g++ and make for the Stockfish build (git is already in the base image).
RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make \
    && rm -rf /var/lib/apt/lists/*

# git-uid-1000 safety and build identity (agents may want to inspect git state).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Clone the upstream project at the pinned revision: shallow, fail closed if
# the hash ever drifts from the pin. Resolved by the author on 2026-09-10 via
# `git ls-remote https://github.com/official-stockfish/Stockfish.git HEAD`;
# it is upstream HEAD at that date. A tag/branch can be force-moved upstream;
# the hash is the pin.
ARG UPSTREAM_SHA=59aae690f91d6f69aac194f447d84b4a2c3be778
RUN git clone --depth 1 https://github.com/official-stockfish/Stockfish.git /app/src \
    && cd /app/src \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# Warm the NNUE evaluation network cache. Current Stockfish embeds a default
# neural-net evaluation file into the binary at link time, and its own
# Makefile downloads it (scripts/net.sh, target `net`) on every build unless
# a validated copy already sits in src/. The trial has no network, so we
# fetch it here with the project's own machinery; the file name is the first
# 12 hex chars of its sha256, so the download is self-validating and any
# substitution would fail the build rather than silently change the engine.
RUN make -C /app/src/src net

WORKDIR /app

COPY files/ /app/