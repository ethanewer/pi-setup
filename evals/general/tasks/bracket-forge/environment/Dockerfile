ARG UPSTREAM_SHA_PARENT=5ea3eb1e95f0338e283f5f0b4681f0891a1cd836
ARG UPSTREAM_SHA_FIX=4733e28ba4f281f643ce93e4089eccbb9a9d5a5a

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The build chain for this tree is the "rustup" toolchain line 1.98.1, the
# same stable line the mining/verification run used (the Ubuntu 24.04 apt
# rustc 1.75 is too old for the tested crates.io resolution). The toolchain
# lives in /opt (read-only for everyone); only /app and the cargo target dir
# under /app/src are writable at trial time.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# Minimal rustup profile: the task only ever runs `cargo` and `rustc` (the
# verifier rebuilds the integration test target offline; the oracle and the
# agent do the same). Docs, clippy and rustfmt are never used, so they stay
# out of the toolchain.
#
# The cargo-home writability fix lives HERE, in the very RUN that installed
# it, because a layer is written once: chmod -R in the same RUN as the
# install costs nothing extra, while a chmod -R in its own later RUN would
# copy every file under /opt/cargo into a second layer. /opt/rustup stays
# read-only for everyone (rustc/cargo only read the toolchain), but cargo
# itself needs to create bookkeeping files (.package-cache, sparse-index
# lock/atomic writes, downloaded crate archives) inside CARGO_HOME, and the
# trial may run as uid 1000; so the whole cargo home is made world-writable.
RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install 1.98.1 --profile minimal \
 && rustup default 1.98.1 \
 && rustc --version && cargo --version \
 && chmod -R a+rwX /opt/cargo \
 && rm -f /tmp/rustup.sh

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
#
# The clone runs as root but the trial may run as root or as uid 1000 (user
# `ubuntu` already exists in the base image), and the warm build below runs
# as uid 1000. The tree's ownership/mode bits are fixed HERE, in the same
# RUN that created it: the layer is written once, so the chmod/chown costs
# nothing extra, and every later RUN (belt check, warm build, trial) already
# sees /app/src in its final end state. A chmod -R in its own later RUN
# would copy every source file into a second layer.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && (chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true)

# Extract the project's own regression test (the file that the fix commit
# adds: regex-automata/tests/dfa/onepass/regression.rs) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so
# upstream test bytes never land in this task tree and the fix commit never
# lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/rust-lang/regex.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:regex-automata/tests/dfa/onepass/regression.rs > /opt/golden/regression.rs \
 && test -s /opt/golden/regression.rs \
 && grep -q "zero_repetition_capture_group" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Warm every cache the trial needs AS uid 1000, so every writable path
# (target/, Cargo.lock, cargo bookkeeping) is owned by uid 1000 from the
# start and /opt stays a read-only toolchain. The warm pass resolves all
# crates.io dependencies (there is no committed Cargo.lock, so this pass
# writes one pinned to today's crates.io state) and compiles the
# regex-automata library plus the `integration` test binary
# (regex-automata/tests/lib.rs) under target/; the trial has no network, so
# this layer IS the warm cache.
WORKDIR /app
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p regex-automata --test integration > /tmp/warm.log 2>&1' ; rc=$?; \
    tail -5 /tmp/warm.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    rm -f /tmp/warm.log
# Second pass: must be fully up-to-date (proves the cache is complete for the
# offline trial, and that /opt/cargo is usable by uid 1000 read-only).
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p regex-automata --test integration 2>&1 | tail -3'

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]