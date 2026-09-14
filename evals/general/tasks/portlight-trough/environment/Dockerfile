ARG UPSTREAM_SHA_PARENT=c96efcb87ab72f14a2a084644308c4a5e98ed820
ARG UPSTREAM_SHA_FIX=873cfbe9ab4271ce1bd30c0b0bbfdfaed652ccf8

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    CARGO_REGISTRY_PROTOCOL=sparse \
    PATH="/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Base build tools + git. `build-essential` provides the system cc/linker a
# Rust build pulls in via the `cc` crate; git is used for the provenance and
# pre-fix reconstruction steps in the verifier. safe.directory is written here
# so the root-owned clone in /app/src works for the trial whether it runs as
# root or as uid 1000.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates git build-essential \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Rust 1.70.0 via rustup, installed into /opt (not /root) so the toolchain and
# registry cache are usable by any trial user. 1.70.0 is the exact era-pinned
# toolchain: newer rustc hard-errors on this 2017 tree's #![deny(unused_imports)]
# re-export path and cfg(cargo-clippy); 1.70.0 builds it cleanly and needs the
# sparse registry protocol (set above) to talk to the current crates.io index.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain 1.70.0 --profile minimal \
 && rustup default 1.70.0 \
 && test "$(rustc --version)" = "rustc 1.70.0 (90c541806 2023-05-31)" \
 && cargo --version \
 && chmod -R a+rwX /opt/rustup /opt/cargo

# Clone the REAL upstream repository (serde-rs/serde) at exactly the parent
# commit, with the shallowest possible history: `git init` + one depth-1 fetch
# of the pinned SHA means the object store in /app/src holds ONLY the parent
# commit. The fix commit is NEVER fetched into this clone; it is asserted
# unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/serde-rs/serde.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && chmod -R a+rwX /app/src \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Warm build at the parent commit. Network exists here, so this layer
# (a) downloads and caches the crates.io registry for every crate the
# workspace needs (serde, serde_derive, serde_test, syn/quote/proc-macro2,
# and the test_suite dev-deps fnv/rustc-serialize) into /opt/cargo, and
# (b) compiles the test_macros test binary into target/ so the trial's
# incremental rebuild is fast. The trial has no network and runs offline.
RUN cd /app/src \
 && (cargo build -p serde -p serde_derive -p serde_test > /tmp/warm.log 2>&1 && tail -2 /tmp/warm.log && echo BUILD_OK) \
 || { echo "WARM BUILD FAILED"; tail -8 /tmp/warm.log; exit 1; } \
 && (cargo test -p serde_test_suite --test test_macros --no-run >> /tmp/warm.log 2>&1 && tail -2 /tmp/warm.log && echo TESTBUILD_OK) \
 || { echo "WARM TESTBUILD FAILED"; tail -8 /tmp/warm.log; exit 1; } \
 && chmod -R a+rwX /opt/cargo \
 && rm -rf /app/src/target \
 && rm -f /tmp/warm.log \
 && echo "warm build ok (registry warmed, artifacts dropped)"

# Extract the project's own regression test for this bug (the fix commit's
# test_suite/tests/test_macros.rs, which appends the "unit with excess content
# (f, g, h)" assertion to test_adjacently_tagged_enum) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit and
# its objects never enter /app/src and no upstream test bytes enter this task
# tree. The whole file is kept (as gunwale-tideway keeps the whole t5514 file)
# so the verifier can plant it and run every previously-existing assertion too.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/serde-rs/serde.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:test_suite/tests/test_macros.rs > /opt/golden/test_macros.rs \
 && test -s /opt/golden/test_macros.rs \
 && grep -q "unit with excess content" /opt/golden/test_macros.rs \
 && cd / && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone. The object
# store holds exactly one commit (the parent), so the commit object and every
# blob the fix introduces are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Pin sha256 of the golden test and of the build/test toolchain, so the
# verifier can detect substitution. A trial running as uid 1000 can write the
# world-writable /opt/cargo and /opt/rustup (to build) but cannot overwrite
# these 0555 root-owned pin files; a root trial could, but the tree scope check
# and the replanted golden + hidden cases still catch a fake there. /opt/golden
# and /opt/pins are read-only for everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/test_macros.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/rustup/toolchains/1.70.0-x86_64-unknown-linux-gnu/bin/rustc \
              /opt/cargo/bin/cargo /usr/bin/gcc /usr/bin/cc /usr/bin/ld \
              /usr/bin/git /usr/bin/bash \
      | sort -k2 > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins \
 && chmod 700 /opt/golden \
 && chmod 444 /opt/pins/*.sha256 \
 && chmod 600 /opt/golden/test_macros.rs \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + toolchain pinned"

# The full offline runtime: the trial and the verifier both build the project
# with no network. All crates are already in /opt/cargo's registry cache, so
# CARGO_NET_OFFLINE=true makes cargo fail fast (rather than hang on a network
# timeout) while still compiling any incremental or clean build from cache.
ENV CARGO_NET_OFFLINE=true

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]
