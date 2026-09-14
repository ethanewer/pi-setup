ARG UPSTREAM_SHA_PARENT=916415857f084e63efda03cf25a67fe7f6d24244
ARG UPSTREAM_SHA_FIX=de2567a4c76fa671005538d6cd841abc44932b9a
ARG RUST_VERSION=1.98.1

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG RUST_VERSION

# The build chain is the "rustup" toolchain line 1.98.1, exactly as the
# mining run used. The repository's Cargo.lock pins every crate version, but
# the toolchain line is not pinned by Cargo.lock, so it is pinned explicitly
# here. The toolchain lives in /opt (read-only for everyone); only /app and
# the cargo target dir under /app/src are writable at trial time.
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential curl ca-certificates git pkg-config \
 && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh \
 && sh /tmp/rustup.sh -y --default-toolchain none \
 && rustup toolchain install --profile minimal ${RUST_VERSION} \
 && rustup default ${RUST_VERSION} \
 && rustc --version && cargo --version \
 && chmod -R a+rwX /opt/cargo \
 && find /opt/cargo/bin /opt/rustup -type d -exec chmod 755 {} \; \
 && find /opt/cargo/bin /opt/rustup -type f -exec chmod 755 {} \; \
 && chmod 755 /opt/cargo/bin /opt/rustup \
 && rm -f /tmp/rustup.sh

# Cargo needs to create bookkeeping files (package cache, sparse-index
# locks, downloaded crate archives) inside CARGO_HOME, and the trial may run
# as uid 1000; make the whole cargo home root world-writable (a+rwX above)
# so the warm pass can run as uid 1000. The toolchain lives under
# /opt/rustup and /opt/cargo/bin; those are chmod'd to root-only 755 right
# here, in the SAME RUN that installed them, so no second copy of the
# toolchain bytes is ever written (a later chmod in its own RUN would
# copy-up every file into a new layer). /opt/cargo's root is bumped back to
# world-writable below so the warm build (as uid 1000) can create the
# registry and package caches; the lock-down RUN tightens it afterwards.
# The toolchain itself stays read-only; only /app and target/ are writable
# at trial time.

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && ( chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true )

# Extract the project's own regression test for this bug (the test that the
# fix commit appends to tests/regression.rs) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so upstream test
# bytes never land in this task tree and the fix commit never lands in
# /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/BurntSushi/ripgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/regression.rs > /opt/golden/regression.rs \
 && test -s /opt/golden/regression.rs \
 && grep -q "r3180_look_around_panic" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` already exists in the base image). Make the tree writable by
# uid 1000 and WARM every cache the trial needs AS that user, so every
# writable path (target/, cargo bookkeeping) is owned by uid 1000 from the
# start and /opt stays a read-only toolchain. The warm pass downloads all
# crates.io dependencies (Cargo.lock-pinned) and compiles the whole
# workspace plus the `rg` binary and the test harness; the trial has no
# network, so this layer IS the warm cache.
WORKDIR /app
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo build > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -5 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls -la /app/src/target/debug/ | grep -vE '\.d$|^total' | head -30; \
    test -x /app/src/target/debug/rg && echo "rg debug binary built" || { echo "no rg binary"; exit 1; }; \
    chmod -R a+rwX /opt/cargo/registry 2>/dev/null || true; \
    chmod 666 /opt/cargo/.package-cache /opt/cargo/.global-cache /opt/cargo/.package-cache-mutate 2>/dev/null || true
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls /app/src/target/debug/ | grep -iE 'integration|^rg$' | tr '\n' ' '; echo "(integration + rg present)"; \
    chmod -R a+rwX /opt/cargo/registry 2>/dev/null || true; \
    chmod 666 /opt/cargo/.package-cache /opt/cargo/.global-cache /opt/cargo/.package-cache-mutate 2>/dev/null || true

# Lock down the toolchain and the golden regression test. The warm passes
# above needed world-writable cargo-home dirs, and those permissions survive
# into the trial container, so an adversarial agent could swap
# /opt/cargo/bin/cargo for a stub that reports success for every build, plant
# a fake integration harness and a fake rg under git-ignored target/, and earn
# reward 1 on an untouched tree (proven during independent review: such a
# stub attack scored 1 with the pre-hardening verifier). Make every
# executable directory root-only, keep the registry + package-cache writable
# (cargo needs their locks and cache bookkeeping at trial time), keep the
# golden test read-only, and record sha256 pins of the toolchain binaries and
# of the golden regression test so the verifier can detect substitution.
RUN chmod 755 /opt/cargo \
 && mkdir -p /opt/pins \
 && sha256sum /opt/cargo/bin/cargo /usr/bin/git /opt/cargo/bin/rustc > /opt/pins/toolchain.sha256 \
 && sha256sum /opt/golden/regression.rs > /opt/pins/golden.sha256 \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/toolchain.sha256 /opt/pins/golden.sha256 /opt/golden/regression.rs \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && echo "toolchain + golden pinned"

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]