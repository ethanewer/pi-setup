ARG UPSTREAM_SHA_PARENT=62da8f94b9aef9f08679e72190f222c84c974af4
ARG UPSTREAM_SHA_FIX=473cf175a2fa973b62c79dabf00892d6feff453a

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The build chain for this tree is the "rustup" toolchain line 1.98.1. The
# repository's Cargo.lock pins every crate, but the toolchain line is not
# pinned by Cargo.lock, so it is pinned explicitly here, exactly as the
# mining run did. The toolchain lives in /opt (read-only for everyone); only
# /app and the cargo target dir under /app/src are writable at trial time.
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
 && chmod -R a+rwX /opt/cargo \
 && rm -f /tmp/rustup.sh

# /opt/rustup stays read-only for everyone (rustc/cargo only read the
# toolchain), but cargo itself needs to create bookkeeping files
# (.package-cache, sparse-index lock/atomic writes, downloaded crate
# archives) inside CARGO_HOME, and the trial may run as uid 1000; make the
# whole cargo home world-writable. The chmod runs in the same layer that
# created /opt/cargo (the toolchain install above), so it is stored once:
# the toolchain itself lives in the 66k-file /opt/rustup tree, which stays
# untouched, and the --profile minimal above drops clippy/rustfmt/docs the
# trial never invokes.

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
#
# Ownership is fixed in this SAME layer: the image is built as root but the
# trial may run as root or as uid 1000 (user `ubuntu` exists in the base
# image), so the whole tree is made a+rwX and chowned to 1000:1000 right
# here. A chown -R in a later RUN would write a second copy of every file
# into a new layer; folding it into the clone layer stores the tree once.
# End state is identical to a separate chown: files 666, dirs 777,
# owner/group ubuntu:ubuntu (created by the warm build's target/ too).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/clap-rs/clap.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chmod -R a+rwX /app/src \
 && { chown -R 1000:1000 /app/src 2>/dev/null || true; }

# Extract the project's own regression test (the file that the fix commit
# extends: tests/builder/hidden_args.rs) into /opt/golden using a THROWAWAY
# clone that is deleted immediately afterwards, so upstream test bytes never
# land in this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/clap-rs/clap.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/builder/hidden_args.rs > /opt/golden/hidden_args.rs \
 && test -s /opt/golden/hidden_args.rs \
 && grep -q "hidden_arg_with_possible_value_with_help" /opt/golden/hidden_args.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# WARM every cache the trial needs AS uid 1000, so every writable path
# (target/, cargo bookkeeping) is owned by uid 1000 from the start and /opt
# stays a read-only toolchain. The warm pass downloads all crates.io
# dependencies (Cargo.lock-pinned) and compiles the clap lib plus every
# trybuild test binary under target/debug/deps; the trial has no network, so
# this layer IS the warm cache. (The tree itself was already chowned to uid
# 1000 in the clone layer above, so the build below writes as its owner.)
WORKDIR /app
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p clap > /tmp/warm.log 2>&1' ; rc=$?; \
    tail -5 /tmp/warm.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls target/debug/deps/ | grep -c '^builder-' | xargs -I{} echo "builder test binaries: {}"; \
    rm -f /tmp/warm.log
# Second pass: must be fully up-to-date (proves the cache is complete for the
# offline trial, and that /opt/cargo is usable by uid 1000 read-only).
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run -p clap 2>&1 | tail -3' 

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]