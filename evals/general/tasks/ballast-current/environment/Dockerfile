# ballast-current: astral-sh/uv — corrupted HTTP cache entries crash uv with
# an arithmetic-overflow panic instead of being rejected as corrupt (upstream
# issue #19799; fix commit 48c4357fe).
#
# The image clones astral-sh/uv SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays it into the tree exactly as the mining
# reproduction did (the regression test file is NEW in the fix commit; its
# `mod cached_client;` wiring in tests/it/main.rs is part of the fix commit
# too), so
#   cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact
# fails inside the image with the mined symptom: a panic `attempt to add with
# overflow` at crates/uv-client/src/cached_client.rs. The fix commit is
# fetched only into a throwaway bare clone that is deleted afterwards, so it
# is never reachable from /app/src/.git; the overlay is copied from
# /opt/golden (no objects are introduced into the working clone at all).
# uv is not a Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json).
#
# The uv-client `it` test harness is pre-built as a cached image layer so the
# agent's fix cycle is one incremental recompile of a single file; the smoke
# layer fails the image build if the mined failing state is not present.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=6353b242d2774244ae2c6b4be1b95c70f84e97ab
ARG FIX_SHA=48c4357fe2517cce464ffa040d75c92be6a7dc71
ARG GOLDEN_CACHED_SHA=e2da48bae43b157a823e5d4f4d1314e1e474740633f5a5c3663cd7777800c7c1
ARG GOLDEN_MAIN_SHA=450c77a2a29294de7f95cd47e0d620c8c685cbbc48bc124a359aea8523ba2ad4

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential pkg-config libssl-dev \
            git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# rustup + cargo under /opt (shared homes) so whichever uid the trial uses
# can read and write the toolchain and caches.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/astral-sh/uv.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/astral-sh/uv.git \
 && git fetch --depth 1 origin $FIX_SHA \
 && mkdir -p /opt/golden \
 && git show $FIX_SHA:crates/uv-client/tests/it/cached_client.rs > /opt/golden/cached_client.rs \
 && git show $FIX_SHA:crates/uv-client/tests/it/main.rs > /opt/golden/main.rs \
 && test "$(sha256sum /opt/golden/cached_client.rs | cut -d' ' -f1)" = "$GOLDEN_CACHED_SHA" \
 && test "$(sha256sum /opt/golden/main.rs | cut -d' ' -f1)" = "$GOLDEN_MAIN_SHA" \
 && grep -q 'reject_overflowing_cache_policy_length' /opt/golden/cached_client.rs \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the fix-era regression test into the working tree --------------
# (cached_client.rs is new in the fix commit; main.rs gains `mod cached_client;`.)
RUN cp /opt/golden/cached_client.rs /app/src/crates/uv-client/tests/it/cached_client.rs \
 && cp /opt/golden/main.rs /app/src/crates/uv-client/tests/it/main.rs \
 && test "$(sha256sum /app/src/crates/uv-client/tests/it/cached_client.rs | cut -d' ' -f1)" = "$GOLDEN_CACHED_SHA" \
 && test "$(sha256sum /app/src/crates/uv-client/tests/it/main.rs | cut -d' ' -f1)" = "$GOLDEN_MAIN_SHA"

# ---- install the pinned toolchain (1.96.0 from rust-toolchain.toml) ----------
RUN cd /app/src && cargo --version && rustc --version

# ---- pre-build the uv-client test harness (cached image layer) ---------------
# Rust toolchain warm-up + registry cache + full dependency tree.
RUN cd /app/src && cargo test -p uv-client --test it --no-run

# ---- smoke: prove the mined failing state is what the image ships ------------
RUN cd /app/src && bash -c 'cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact > /tmp/smoke.log 2>&1; \
    grep -qF "attempt to add with overflow" /tmp/smoke.log && grep -qF "1 failed" /tmp/smoke.log' \
 && grep -q 'reject_overflowing_cache_policy_length' /tmp/smoke.log

# ---- record the real cargo binary's digest -----------------------------------
# The verifier compares `command -v cargo` against this digest, so a wrapper or
# fake binary shadowing the rustup proxy cannot fake the harness runs while the
# bug remains in the tree. Computed in the same image that ships to the trial,
# so it is always consistent with what the trial sees.
RUN sha256sum "$(command -v cargo)" | cut -d' ' -f1 > /opt/golden/cargo.sha256 \
 && test -s /opt/golden/cargo.sha256

# ---- offline from here on: the trial container has no network ---------------
RUN mkdir -p /opt/cargo && printf '[net]\noffline = true\n' > /opt/cargo/config.toml

# The build above ran as root. Trials on this host run as root, and the
# surgical top-level chmod below keeps the source tree usable by any uid
# without walking the multi-GiB cargo artifact dir on every image build.
RUN chmod a+rwX /app/src /app /opt/cargo /opt/rustup /opt/golden

WORKDIR /app

CMD ["/bin/bash"]