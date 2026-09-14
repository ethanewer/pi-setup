ARG UPSTREAM_SHA_PARENT=fb9435d026ab011c9071ca92eeab738b9b30ca13
ARG UPSTREAM_SHA_FIX=8c92ef6c76686a642e748919f33587561c2a0280

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The build chain for this tree is the "rustup" toolchain line 1.98.1. The
# repository's Cargo.lock pins every crate, but the toolchain line is not
# pinned by Cargo.lock, so it is pinned explicitly here, exactly as the
# mining run did. The toolchain lives in /opt (read-only for everyone); only
# /app and the cargo target dir under /app/src are writable at trial time.
# The `--profile minimal` component set (rustc, cargo, rust-std) is enough:
# the task and verifier only use `cargo test`/`cargo`/`rustc`, never
# clippy/rustfmt/rust-docs, so the ~1 GB of docs and lint/formatter binaries
# are not installed. The cargo-home chmod is folded into this same RUN so the
# writable tree is created with the right modes once (a separate `chmod -R`
# RUN would copy every file under /opt/cargo into a second layer).
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install 1.98.1 --profile minimal \
 && rustup default 1.98.1 \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh \
 && chmod -R a+rwX /opt/cargo

# /opt/rustup stays read-only for everyone (rustc/cargo only read the
# toolchain); the cargo home was made world-writable (a+rwX) at the end of
# the toolchain RUN above so cargo can create its bookkeeping files
# (.package-cache, sparse-index lock/atomic writes, downloaded crate
# archives) under CARGO_HOME whether the trial runs as root or uid 1000.

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone. The writable-by-uid-1000 modes/ownership are set
# in this same RUN so the tree bytes are stored once, not copied into a
# second layer by a later `chmod -R`/`chown -R` of its own.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/clap-rs/clap.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && (chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true)

# Extract the project's own regression test (tests/builder/help.rs exactly as
# it exists at the fix commit, i.e. the parent's file plus the added
# `hidden_possible_vals` regression test) into /opt/golden using a THROWAWAY
# clone that is deleted immediately afterwards, so upstream test bytes never
# land in this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/clap-rs/clap.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/builder/help.rs > /opt/golden/help.rs \
 && test -s /opt/golden/help.rs \
 && grep -q "hidden_possible_vals" /opt/golden/help.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` already exists in the base image). The tree was already made
# writable by uid 1000 (mode a+rwX, owner 1000:1000) in the clone RUN; now we
# WARM every cache the trial needs AS that user, so every writable path
# (target/, cargo bookkeeping) is owned by uid 1000 from the start and /opt
# stays a read-only toolchain. The warm pass downloads all crates.io
# dependencies (Cargo.lock-pinned) and compiles the clap lib plus every
# trybuild test binary under target/debug/deps; the trial has no network, so
# this layer IS the warm cache.
WORKDIR /app
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p clap > /tmp/warm.log 2>&1' ; rc=$?; \
    tail -5 /tmp/warm.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls /app/src/target/debug/deps/ | grep -c '^builder-' | xargs -I{} echo "builder test binaries: {}"; \
    rm -f /tmp/warm.log
# Second pass: must be fully up-to-date (proves the cache is complete for the
# offline trial, and that /opt/cargo is usable by uid 1000 read-only).
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p clap 2>&1 | tail -3'

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]
