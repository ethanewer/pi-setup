# bracket-gate: serde internally-tagged struct with a flattened tagged enum
# serializes the wrong tag (issue #1468).
#
# The image clones serde-rs/serde SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit
# is a descendant of the parent, so it is NOT reachable from the depth-1 clone
# the agent works on; the extraction uses a throwaway bare clone that is
# deleted before the image build continues, and the working clone's object
# database is asserted to lack the fix commit at build time and again by the
# verifier at trial time.
#
# Toolchain: rustup 1.88.0 (RUSTUP_TOOLCHAIN=1.88.0). Newer rustc versions
# hard-error on this era's derive code, and the reproduction only fails on
# 1.88.0, so the exact toolchain is pinned. The warm build happens here as a
# cached image layer: at trial time there is no network and the agent's work
# is an incremental rebuild on top of /app/src/target.
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=bb99b31eb0a55393101f9c80cd959b3a739ad70f
ARG FIX_SHA=1d6ef76cfb339df48232b59cc2ce8568fd19660c

# Rust lives in /opt so that an arbitrary uid (harbor may run the trial as
# uid 1000) can read and write it.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH \
    RUSTUP_TOOLCHAIN=1.88.0 \
    RUST_BACKTRACE=1 \
    PIP_NO_CACHE_DIR=1

# A C compiler is needed by the era's proc-macro build tooling; the base
# image does not carry one.
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

# ---- rustup + pinned toolchain ---------------------------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
     | sh -s -- -y --default-toolchain 1.88.0 \
 && rustup default 1.88.0 \
 && rustc --version | grep -q '^rustc 1\.88\.0' \
 && cargo --version | grep -q '^cargo 1\.88\.0'

# ---- git identity and safe directories -------------------------------------
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
RUN git clone --depth 1 https://github.com/serde-rs/serde.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin bb99b31eb0a55393101f9c80cd959b3a739ad70f \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/serde-rs/serde.git \
 && git fetch --depth 1 origin 1d6ef76cfb339df48232b59cc2ce8568fd19660c \
 && mkdir -p /opt/golden \
 && git show 1d6ef76cfb339df48232b59cc2ce8568fd19660c:test_suite/tests/test_macros.rs \
      > /opt/golden/test_macros.rs \
 && test -s /opt/golden/test_macros.rs \
 && grep -q "test_internally_tagged_struct_with_flattened_field" /opt/golden/test_macros.rs \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm build: everything the trial will compile, built once -------------
# Builds the serde_test_suite test binary (and every row of its dep graph:
# serde, serde_derive, serde_derive_internals, serde_test, plus the crates.io
# dev-dependencies fnv and rustc-serialize) and records their cargo registry
# cache. The test binary running here is the PARENT version of test_macros.rs
# (bug present, no regression test yet); it is green on 1.88.0.
RUN cd /app/src \
 && cargo test -p serde_test_suite --test test_macros --no-run \
 && cargo test -p serde_test_suite --test test_macros -q

# From here on cargo must never touch the network (trial mode).
ENV CARGO_NET_OFFLINE=true

# ---- harness integrity manifests (root-owned; read-only to the trial) --------
# The verifier recomputes these hashes at trial time and fails on any
# difference, so the golden test, the cargo/rustc binaries and the crates.io
# source extracts cannot be re-pointed or tampered with to fake a pass.
RUN mkdir -p /opt/harness \
 && : > /opt/cargo/config.toml \
 && sha256sum /opt/cargo/bin/rustup \
      /opt/cargo/config.toml \
      /opt/rustup/toolchains/*/bin/cargo \
      /opt/rustup/toolchains/*/bin/rustc \
      > /opt/harness/toolchain.sha256 \
 && sha256sum /opt/golden/test_macros.rs > /opt/harness/golden.sha256 \
 && (cd /opt/cargo/registry/src && find . -type f -print0 | sort -z | xargs -0 sha256sum) \
      > /opt/harness/registry-src.sha256 \
 && test -s /opt/harness/toolchain.sha256 \
 && test -s /opt/harness/golden.sha256 \
 && test -s /opt/harness/registry-src.sha256 \
 && grep -q "test_internally_tagged_struct_with_flattened_field" /opt/golden/test_macros.rs

WORKDIR /app

COPY files/ /app/

# The trial may run as a non-root uid; give it full access to the clone, the
# cargo/rustup roots and whatever the agent produces.
RUN chmod -R a+rwX /app /opt/cargo /opt/rustup

CMD ["/bin/bash"]