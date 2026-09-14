ARG UPSTREAM_SHA_PARENT=bb88a1ac45c70bef97e0d6ccd6e91595610de860
ARG UPSTREAM_SHA_FIX=0407e104f611d623547897ca99d172673b31779f
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
 && rustup toolchain install ${RUST_VERSION} \
 && rustup default ${RUST_VERSION} \
 && rustc --version && cargo --version \
 && rm -f /tmp/rustup.sh

# Cargo needs to create bookkeeping files (package cache, sparse-index
# locks, downloaded crate archives) inside CARGO_HOME, and the trial may run
# as uid 1000; make the whole cargo home world-writable (matching the
# sibling v4.2 Rust tasks).
RUN chmod -R a+rwX /opt/cargo

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
 && git config --system user.name "build"

# The image is built as root; the trial may run as root or as uid 1000
# (user `ubuntu` already exists in the base image). Make the tree writable by
# uid 1000 and WARM every cache the trial needs AS that user, so every
# writable path (target/, cargo bookkeeping) is owned by uid 1000 from the
# start and /opt stays a read-only toolchain. The warm pass downloads all
# crates.io dependencies (Cargo.lock-pinned) and compiles the whole
# workspace plus the `rg` binary and the test harness; the trial has no
# network, so this layer IS the warm cache.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true
RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo build > /tmp/warm1.log 2>&1'; rc=$?; \
    tail -3 /tmp/warm1.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit $rc; fi; \
    test -x /app/src/target/debug/rg || { echo "no rg binary"; exit 1; }

# Bake a pristine PRE-FIX `rg` debug binary (built at the parent commit above)
# at /opt/prefix/rg. The verifier runs the agent's own reproduction against
# this binary and requires it to FAIL, proving the symptom is real and that
# the reproduction targets it.
RUN mkdir -p /opt/prefix \
 && cp /app/src/target/debug/rg /opt/prefix/rg \
 && test -x /opt/prefix/rg \
 && chmod 755 /opt/prefix/rg

# Fail closed inside the image: the bug must reproduce with the parent
# binary this image ships. The reproduction is the exception: hidden file
# whitelisted by `!.foo.txt` in a parent .ignore, searched from the subdir
# with the path spelled `.` must print NOTHING and exit nonzero (that is the
# bug); from the same subdir with no path it must print the file (proving the
# scenario is otherwise valid). This is the parent-direction confirmation in
# this exact image.
RUN rm -rf /tmp/reprocheck \
 && mkdir -p /tmp/reprocheck/subdir \
 && printf 'text\n' > /tmp/reprocheck/subdir/.foo.txt \
 && printf '!.foo.txt\n' > /tmp/reprocheck/.ignore \
 && cd /tmp/reprocheck/subdir \
 && /app/src/target/debug/rg --files > /tmp/bugcheck-noarg.out 2>&1; rc1=$?; cat /tmp/bugcheck-noarg.out \
 && cd /tmp/reprocheck/subdir \
 && /app/src/target/debug/rg --files . > /tmp/bugcheck-dot.out 2>&1; rc2=$?; cat /tmp/bugcheck-dot.out \
 && [ -s /tmp/bugcheck-noarg.out ] && grep -q '.foo.txt' /tmp/bugcheck-noarg.out \
 && [ "$rc1" -eq 0 ] \
 && [ ! -s /tmp/bugcheck-dot.out ] && [ "$rc2" -ne 0 ] \
 && rm -rf /tmp/reprocheck /tmp/bugcheck-noarg.out /tmp/bugcheck-dot.out \
 && echo "parent-direction reproduction confirmed in image" \
 || { echo "REPRODUCTION CHECK FAILED (rc1=$rc1 rc2=$rc2)"; exit 1; }

RUN su -s /bin/bash ubuntu -c 'cd /app/src && export PATH="/opt/cargo/bin:$PATH" && \
    cargo test --no-run > /tmp/warm2.log 2>&1'; rc=$?; \
    tail -3 /tmp/warm2.log; \
    if [ $rc -ne 0 ]; then echo "WARM TEST-BUILD FAILED (exit $rc)"; exit $rc; fi; \
    ls /app/src/target/debug/deps/ | grep -iE '^integration' | tr '\n' ' '; echo "(integration harness present)"

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
 && grep -q "r3173_hidden_whitelist_only_dot" /opt/golden/regression.rs \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Lock down the toolchain, the golden regression test and the pre-fix
# binary. The warm passes above needed world-writable cargo-home dirs, and
# those permissions survive into the trial container, so an adversarial
# agent (a root trial) could swap /opt/cargo/bin/cargo for a stub that
# reports success for every build or replace /opt/prefix/rg so the pre-fix
# check fails to fail; record sha256 pins of the toolchain binaries, of the
# golden test and of the pre-fix binary so the verifier can detect
# substitution.
RUN chmod 755 /opt/cargo /opt/cargo/bin /opt/rustup /opt/prefix \
 && find /opt/cargo/bin /opt/rustup -type d -exec chmod 755 {} \; \
 && find /opt/cargo/bin /opt/rustup -type f -exec chmod 755 {} \; \
 && chmod -R a+rwX /opt/cargo/registry \
 && chmod 666 /opt/cargo/.global-cache /opt/cargo/.package-cache /opt/cargo/.package-cache-mutate \
 && mkdir -p /opt/pins \
 && sha256sum /opt/cargo/bin/cargo /usr/bin/git /opt/cargo/bin/rustc > /opt/pins/toolchain.sha256 \
 && sha256sum /opt/golden/regression.rs > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/rg > /opt/pins/prefix-rg.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/toolchain.sha256 /opt/pins/golden.sha256 /opt/pins/prefix-rg.sha256 /opt/golden/regression.rs \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null \
 && echo "toolchain + golden + prefix binary pinned"

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]