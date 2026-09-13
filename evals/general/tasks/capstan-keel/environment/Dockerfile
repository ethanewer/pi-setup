# capstan-keel: uv cache clean reports the wrong amount of space reclaimed.
#
# The image clones astral-sh/uv SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and at build time extracts the
# project's own regression tests for the bug from the FIX commit into
# /opt/golden/ (upstream test bytes never enter this repository; the task tree
# is byte-audited). The fix commit is a descendant of the parent, so it is NOT
# reachable from the depth-1 clone the agent works on; the extraction uses a
# throwaway bare clone that is deleted immediately after.
#
# The candidate fix changes a few crates; the golden crate-level regression
# test (crates/uv-cache/tests/removal.rs) exercises the fixed accounting API.
# Because the upstream fix also RENAMED that internal API
# (logical_bytes/physical_bytes -> coarse_bytes/fine_bytes, RemovalMode ->
# RemovalAccounting), the extracted golden file only compiles against a tree
# that reproduces the rename.  A functionally correct fix that keeps the old
# names is equally valid, so the verifier also runs a name-translated variant
# (coarse_bytes -> logical_bytes, generated here by sed) and accepts either.
# The oracle applies the minimal, name-preserving fix; agents may do either.
#
# Pure-CLI observation is the common oracle: `Removed N files (X)` where X is
# computed from allocated blocks with hardlinks counted once.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=64c73b115b544e8424a8c69f44131e21d66e629c
ARG FIX_SHA=fab2c0c0d2992217ff8768d11558f4b668d02501
ARG RUST_CHANNEL=1.98.0

# ---- toolchain: rust 1.98.0 (pinned by rust-toolchain.toml at this commit) --
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH

RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUST_CHANNEL" \
 && rustup default "$RUST_CHANNEL" \
 && rustc --version \
 && cargo --version

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.  The fix
# commit is a descendant, never fetched, so its objects are absent from this
# clone's object store.
RUN git clone --depth 1 https://github.com/astral-sh/uv.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression tests from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/astral-sh/uv.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA":crates/uv-cache/tests/removal.rs \
        > /opt/golden/removal.rs \
 && git show "$FIX_SHA":crates/uv/tests/build/cache_clean.rs \
        > /opt/golden/cache_clean.rs \
 && git show "$FIX_SHA":crates/uv/tests/build/cache_prune.rs \
        > /opt/golden/cache_prune.rs \
 && test -s /opt/golden/removal.rs && grep -q 'coarse_bytes' /opt/golden/removal.rs \
 && sed -e 's/coarse_bytes/logical_bytes/g' /opt/golden/removal.rs \
        > /opt/golden/removal_legacy_api.rs \
 && grep -q 'logical_bytes' /opt/golden/removal_legacy_api.rs \
 && sha256sum /opt/golden/*.rs | tee /opt/golden/SHA256SUMS \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm every cache at build time (trial is offline) ----------------------
# Full debug build of the `uv` binary with the parent tree, done here on many
# cores so the agent's first reproduction costs nothing and its rebuild of the
# changed crates is incremental.  Also warms the crates.io registry cache.
WORKDIR /app/src
RUN cargo build -p uv

# Everything from here on must work without the network; fail loudly instead
# of silently re-resolving dependencies.
ENV CARGO_NET_OFFLINE=true

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]